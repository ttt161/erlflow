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
    flow_info/2,
    collect/0,
    collect/1
]).

-include_lib("netflow/include/netflow_v5.hrl").
-include("erlflow.hrl").

-define(SERVER, ?MODULE).

-define(NEW_FLOW, #nfrec_v5{d_pkts = 0, d_octets = 0}).


-record(erlflow_collector_state, {
    flows = #{},
    timers = #{},
    bytes_accumulator = 0,
    packets_accumulator = 0,
    last_collected_ts,
    attributes = #{},
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

collect() ->
    collect(<<>>).

collect(InitAcc) ->
    ConstructorMod = application:get_env(erlflow, metric_constructor, undefined),
    {ok, RegisterTable} = erlflow_register:all_collectors(),
    Result = lists:foldl(fun({_Name, Pid}, Acc) ->
        try gen_server:call(Pid, {collect, ConstructorMod}) of
            {ok, Metrics} -> metrics_concat(ConstructorMod, Metrics, Acc)
        catch _:_ -> Acc
        end
    end, InitAcc, RegisterTable),
    assemble_metrics(ConstructorMod, Result).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start(Hash, FlowRec, Attributes, Suffix) ->
    supervisor:start_child(erlflow_collector_sup, [Hash, FlowRec, Attributes, Suffix]).

start_link(Hash, FlowRec, Attributes, Suffix) ->
    gen_server:start_link({via, erlflow_register, Hash}, ?MODULE, [FlowRec, Attributes, Suffix], []).

init([FlowRec, Attributes, Suffix]) ->
    ConstructorMod = application:get_env(erlflow, metric_constructor, undefined),
    {LabelNames, LabelValues} = lists:unzip(maps:to_list(Attributes)),
    BytesKey = erlang:list_to_atom("netflow_bytes_sent" ++ Suffix),
    PacketsKey = erlang:list_to_atom("netflow_packets_sent" ++ Suffix),
    case ConstructorMod of
        undefined ->
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
            ]);
        Module ->
            Module:create_metrics(Attributes)
    end,
    NewState = process(FlowRec, #erlflow_collector_state{}),
    {ok, NewState#erlflow_collector_state{last_collected_ts = erlang:system_time(nanosecond), labels = LabelValues,
        attributes = Attributes, bytes_key = BytesKey, packets_key = PacketsKey}}.

handle_call({collect, ConstructorMod}, _From, State = #erlflow_collector_state{
        last_collected_ts = LastTs,
        bytes_accumulator = BytesAcc,
        packets_accumulator = PackAcc,
        attributes = Attributes,
        labels = Labels,
        bytes_key = BytesKey,
        packets_key = PacketsKey}) ->

    NowTs = erlang:system_time(nanosecond),
    Metrics = case ConstructorMod of
        undefined ->
            update_prometheus_metrics(BytesAcc, PackAcc, Labels, BytesKey, PacketsKey);
        Module ->
            BaseMap = #{
                timestamp_nano => NowTs,
                start_timestamp_nano => LastTs,
                attributes => Attributes
            },
            Data = [
                BaseMap#{key => BytesKey, value => BytesAcc},
                BaseMap#{key => PacketsKey, value => PackAcc}
            ],
            Module:update_metrics(Data)
    end,
    {reply, {ok, Metrics}, State#erlflow_collector_state{last_collected_ts = NowTs, bytes_accumulator = 0, packets_accumulator = 0}};
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
        bytes_accumulator = BytesAcc, packets_accumulator = PacketAcc} = State) ->

    Key = ?FLOW_SIGN(FlowRec),
    #nfrec_v5{
        d_octets = LastBytes,
        d_pkts = LastPackets
    } = maps:get(Key, Flows, ?NEW_FLOW),
    NewTref = restart_timer(Key, Timers),
    %% TODO
    State#erlflow_collector_state{
        flows = Flows#{Key => FlowRec},
        timers = Timers#{Key => NewTref},
        bytes_accumulator = Bytes - LastBytes + BytesAcc,
        packets_accumulator = Packets - LastPackets + PacketAcc
    }.

restart_timer(Key, Timers) when is_map_key(Key, Timers) ->
    OldTref = maps:get(Key, Timers),
    erlang:cancel_timer(OldTref),
    erlang:start_timer(?INACTIVITY_TIMEOUT, self(), {drop_flow_info, Key});
restart_timer(Key, _Timers) ->
    erlang:start_timer(?INACTIVITY_TIMEOUT, self(), {drop_flow_info, Key}).

update_prometheus_metrics(Bytes, Packets, Labels, BytesKey, PacketsKey) ->
    prometheus_counter:inc(erlflow, BytesKey, Labels, Bytes),
    prometheus_counter:inc(erlflow, PacketsKey, Labels, Packets).

metrics_concat(undefined, _Metrics, _Acc) ->
    skip;
metrics_concat(Module, Metrics, Acc) ->
    Module:metrics_concat(Metrics, Acc).

assemble_metrics(undefined, _Result) ->
    prometheus_text_format:format(erlflow);
assemble_metrics(Module, Result) ->
    Module:assemble_metrics(Result).
