%%%-------------------------------------------------------------------
%%% @author losto
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(erlflow_collector).

-behaviour(gen_server).

-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).

-export([
    flow_info/2
]).

-include_lib("netflow/include/netflow_v5.hrl").
-include("erlflow.hrl").

-define(SERVER, ?MODULE).

-define(NEW_FLOW, #nfrec_v5{d_pkts = 0, d_octets = 0}).


-record(erlflow_collector_state, {
    flows = #{},
    timers = #{},
    labels = <<>>,
    bytes_key,
    packets_key
}).

%%%===================================================================
%%% API
%%%===================================================================

flow_info(_FlowRec, reject) -> skip;
flow_info(FlowRec, {Suffix, Attributes}) ->
    Hash = xxhash:hash64(term_to_binary(Attributes)),
    case erlflow_register:whereis_name(Hash) of
        undefined -> start(Hash, FlowRec, Attributes, Suffix);
        Pid when is_pid(Pid) -> gen_server:cast(Pid, {flow_info, FlowRec})
    end.

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start(Hash, FlowRec, Attributes, Suffix) ->
    supervisor:start_child(erlflow_collector_sup, [Hash, FlowRec, Attributes, Suffix]).

start_link(Hash, FlowRec, Attributes, Suffix) ->
    gen_server:start_link({via, erlflow_register, Hash}, ?MODULE, [FlowRec, Attributes, Suffix], []).

init([FlowRec, Attributes, Suffix]) ->
    {LabelNames, LabelValues} = lists:unzip(maps:to_list(Attributes)),
    BytesKey = erlang:list_to_atom("netflow_bytes_sent" ++ Suffix),
    PacketsKey = erlang:list_to_atom("netflow_packets_sent" ++ Suffix),
    prometheus_counter:declare([
        {registry, erlflow},
        {name, BytesKey},
        {help, "The total bytes sent in direction"},
        {labels, LabelNames}
    ]),
    prometheus_counter:declare([
        {registry, erlflow},
        {name, PacketsKey},
        {help, "The total packets sent in direction"},
        {labels, LabelNames}
    ]),
    NewState = process(FlowRec, #erlflow_collector_state{labels = LabelValues, bytes_key = BytesKey, packets_key = PacketsKey}),
    {ok, NewState}.

handle_call(_Request, _From, State = #erlflow_collector_state{}) ->
    {reply, ok, State}.

handle_cast({flow_info, FlowRec}, State) ->
    NewState = process(FlowRec, State),
    {noreply, NewState};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({timeout, _TRef, {drop_flow_info, Key}}, State = #erlflow_collector_state{flows = Flows, timers = Timers}) ->
    {noreply, State#erlflow_collector_state{flows = maps:without([Key], Flows), timers = maps:without([Key], Timers)}};
handle_info(_Info, State = #erlflow_collector_state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #erlflow_collector_state{}) ->
    ok.

code_change(_OldVsn, State = #erlflow_collector_state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

process(#nfrec_v5{d_octets = Bytes, d_pkts = Packets} = FlowRec, #erlflow_collector_state{flows = Flows, timers = Timers,
        labels = Labels, bytes_key = BytesKey, packets_key = PacketsKey} = State) ->

    Key = erlflow_utils:flow_sign(FlowRec),
    #nfrec_v5{
        d_octets = LastBytes,
        d_pkts = LastPackets
    } = maps:get(Key, Flows, ?NEW_FLOW),
    NewTref = restart_timer(Key, Timers),
    prometheus_counter:inc(erlflow, BytesKey, Labels, unsigned_delta(Bytes, LastBytes)),
    prometheus_counter:inc(erlflow, PacketsKey, Labels, unsigned_delta(Packets, LastPackets)),
    State#erlflow_collector_state{
        flows = Flows#{Key => FlowRec},
        timers = Timers#{Key => NewTref}
    }.

restart_timer(Key, Timers) when is_map_key(Key, Timers) ->
    OldTref = maps:get(Key, Timers),
    erlang:cancel_timer(OldTref),
    erlang:start_timer(?INACTIVITY_TIMEOUT, self(), {drop_flow_info, Key});
restart_timer(Key, _Timers) ->
    erlang:start_timer(?INACTIVITY_TIMEOUT, self(), {drop_flow_info, Key}).

unsigned_delta(Current, Last) when Current > Last -> Current - Last;
unsigned_delta(_Current, _Last) -> 0.