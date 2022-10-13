%%%-------------------------------------------------------------------
%%% @author losto
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(erlflow).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_ATTRS, [
    "src_addr",
    "dst_addr",
    "proto",
    "port",
    "tos"
]).
-define(ALL_ATTRS, [
    "src_addr",
    "dst_addr",
    "proto",
    "src_port",
    "dst_port",
    "port",
    "tos"
]).
-define(DEFAULT_CONFIG_PATH, "config/config.yml").
-define(DEFAULT_LISTEN_PORT, 9555).
-define(DEFAULT_DYNAMIC_PORTS, {49152, 65535}).

-include_lib("netflow/include/netflow_v5.hrl").

-record(erlflow_state, {socket, rules}).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    Rules = read_config(),
    ListenPort = application:get_env(erlflow, port, ?DEFAULT_LISTEN_PORT),
    {ok, Sock} = gen_udp:open(ListenPort, [binary, {active, once}]),
    {ok, #erlflow_state{socket = Sock, rules = Rules}}.

handle_call(_Request, _From, State = #erlflow_state{}) ->
    {reply, ok, State}.

handle_cast(_Request, State = #erlflow_state{}) ->
    {noreply, State}.

handle_info({udp, Socket, SensorAddress, _SensorPort, Payload}, State = #erlflow_state{rules = Rules}) ->
    try netflow_v5_codec:decode(Payload) of
        {ok, {#nfh_v5{}, RecordsList}} -> process(SensorAddress, RecordsList, Rules)
    catch _Ex:_Er ->
        %% TODO log
        io:format("CANT DECODE: ~p~n///~n~p~n", [_Ex, _Er])
    end,
    inet:setopts(Socket, [{active, once}, binary]),
    {noreply, State};
handle_info(_Info, State = #erlflow_state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #erlflow_state{}) ->
    ok.

code_change(_OldVsn, State = #erlflow_state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

read_config() ->
    ConfigPath = application:get_env(erlflow, config_path, ?DEFAULT_CONFIG_PATH),
    [ConfigYaml] = yamerl:decode_file(ConfigPath),
    ConfigMaps = erlflow_utils:from_list_recursive(ConfigYaml),
    parse_config(ConfigMaps).

parse_config(ConfigMaps) ->
    lists:foldr(fun(RawRule, Acc) -> [maps:to_list(parse_rule(RawRule)) | Acc] end, [], ConfigMaps).

parse_rule(RawRule) ->
    maps:fold(fun
        ("src_addr", Value, Acc) -> Acc#{src_addr => parse_addr(Value)};
        ("dst_addr", Value, Acc) -> Acc#{dst_addr => parse_addr(Value)};
        ("src_port", Value, Acc) -> Acc#{src_port => parse_port(Value)};
        ("dst_port", Value, Acc) -> Acc#{dst_port => parse_port(Value)};
        ("port", Value, Acc) -> Acc#{port => parse_port(Value)};
        ("proto", Value, Acc) -> Acc#{proto => parse_proto(Value)};
        ("tos", Value, Acc) -> Acc#{src_port => parse_tos(Value)};
        ("action", Value, Acc) -> Acc#{action => parse_action(Value)};
        (_, _, Acc) -> Acc
    end, #{}, RawRule).

parse_addr(Condition) ->
    {Act, Value} = parse_condition(Condition),
    [Network, Mask] = string:split(Value, "/"),
    {ok, {A, B, C, D}} = inet:parse_address(Network),
    {Act, {<<A, B, C, D>>, validate_range(Mask, 0, 32)}}.

parse_port(Condition) when is_map(Condition) ->
    Tuple = parse_condition(Condition),
    parse_port(Tuple);
parse_port({Act, Value}) when is_list(Value) ->
    [Min, Max] = string:split(Value, "-"),
    {Act, {validate_range(Min, 0, 65535), validate_range(Max, 0, 65535)}};
parse_port({Act, Value}) when is_integer(Value) ->
    Value = validate_range(Value, 0, 65535),
    {Act, {Value, Value}}.

parse_proto(Condition) ->
    {Act, Value} = parse_condition(Condition),
    {Act, validate_range(Value, 1, 252)}.

parse_tos(Condition) ->
    {Act, Value} = parse_condition(Condition),
    {Act, validate_range(Value, 0, 255)}.

parse_action("reject") -> reject;
parse_action(#{"key_suffix" := Suffix} = Action) ->
    #{
        key_suffix => Suffix,
        attributes => maps:get("attributes", Action, ?DEFAULT_ATTRS),
        ext_attributes => maps:get("ext_attributes", Action, #{})
    }.

validate_range(Value, Min, Max) when is_list(Value) ->
    {Int, _} = string:to_integer(Value),
    validate_range(Int, Min, Max);
validate_range(Value, Min, Max) when is_integer(Value) ->
    case Value >= Min andalso Value =< Max of
        true -> Value;
        false -> throw({error, bad_config_param})
    end.

parse_condition(Condition) ->
    case Condition of
        #{"match" := Val} -> {match, Val};
        #{"dismatch" := Val} -> {dismatch, Val}
    end.

process(SensorAddress, RecordsList, Rules) ->
    lists:foreach(fun(FlowRec) ->
        %% TODO add cache #{flow_sign => MetaData}
        case match_rules(SensorAddress, FlowRec, Rules) of
            reject -> skip;
            {ok, MetaData} -> erlflow_collector:flow_info(FlowRec, MetaData)
        end
    end, RecordsList).

match_rules(_SensorAddress, _FlowRec, []) -> reject;
match_rules(SensorAddress, FlowRec, [Rule | Rest]) ->
    case match(Rule, FlowRec) of
        true ->
            case lists:keyfind(action, 1, Rule) of
                {action, reject} -> reject;
                {action, #{key_suffix := Suffix, attributes := Attrs, ext_attributes := ExtAttrs}} ->
                    VectorAttributes = assemble_attributes(Attrs, ExtAttrs, FlowRec, SensorAddress),
                    {ok, {Suffix, VectorAttributes}}
            end;
        false ->
            match_rules(SensorAddress, FlowRec, Rest)
    end.

match(Rule, FlowRec) ->
    match(Rule, FlowRec, true).

match(_Rule, _FlowRec, false) -> false;
match([], _FlowRec, Result) -> Result;
match([{action, _} | Rest], FlowRec, Acc) -> match(Rest, FlowRec, Acc);
match([{src_addr, {match, {Net, Mask}}} | Rest], #nfrec_v5{src_addr = Addr} = FlowRec, _) ->
    BinIP = to_binary_ip(Addr),
    match(Rest, FlowRec, <<Net:Mask/bits>> =:= <<BinIP:Mask/bits>>);
match([{src_addr, {dismatch, {Net, Mask}}} | Rest], #nfrec_v5{src_addr = Addr} = FlowRec, _) ->
    BinIP = to_binary_ip(Addr),
    match(Rest, FlowRec, <<Net:Mask/bits>> =/= <<BinIP:Mask/bits>>);
match([{dst_addr, {match, {Net, Mask}}} | Rest], #nfrec_v5{dst_addr = Addr} = FlowRec, _) ->
    BinIP = to_binary_ip(Addr),
    match(Rest, FlowRec, <<Net:Mask/bits>> =:= <<BinIP:Mask/bits>>);
match([{dst_addr, {dismatch, {Net, Mask}}} | Rest], #nfrec_v5{dst_addr = Addr} = FlowRec, _) ->
    BinIP = to_binary_ip(Addr),
    match(Rest, FlowRec, <<Net:Mask/bits>> =/= <<BinIP:Mask/bits>>);
match([{proto, {match, ProtoExpected}} | Rest], #nfrec_v5{prot = Proto} = FlowRec, _) ->
    match(Rest, FlowRec, ProtoExpected =:= Proto);
match([{proto, {dismatch, ProtoExpected}} | Rest], #nfrec_v5{prot = Proto} = FlowRec, _) ->
    match(Rest, FlowRec, ProtoExpected =/= Proto);
match([{src_port, {match, {_Min, _Max}=Range}} | Rest], #nfrec_v5{src_port = Port} = FlowRec, _) ->
    match(Rest, FlowRec, check_range(Port, Range));
match([{src_port, {dismatch, {_Min, _Max}=Range}} | Rest], #nfrec_v5{src_port = Port} = FlowRec, _) ->
    match(Rest, FlowRec, not check_range(Port, Range));
match([{dst_port, {match, {_Min, _Max}=Range}} | Rest], #nfrec_v5{dst_port = Port} = FlowRec, _) ->
    match(Rest, FlowRec, check_range(Port, Range));
match([{dst_port, {dismatch, {_Min, _Max}=Range}} | Rest], #nfrec_v5{dst_port = Port} = FlowRec, _) ->
    match(Rest, FlowRec, not check_range(Port, Range));
match([{port, {match, {_Min, _Max}=Range}} | Rest], #nfrec_v5{src_port = SPort, dst_port = DPort} = FlowRec, _) ->
    Port = base_port(SPort, DPort),
    match(Rest, FlowRec, check_range(Port, Range));
match([{port, {dismatch, {_Min, _Max}=Range}} | Rest], #nfrec_v5{src_port = SPort, dst_port = DPort} = FlowRec, _) ->
    Port = base_port(SPort, DPort),
    match(Rest, FlowRec, not check_range(Port, Range));
match([{tos, {match, TosExpected}} | Rest], #nfrec_v5{tos = Tos} = FlowRec, _) ->
    match(Rest, FlowRec, TosExpected =:= Tos);
match([{tos, {dismatch, TosExpected}} | Rest], #nfrec_v5{tos = Tos} = FlowRec, _) ->
    match(Rest, FlowRec, TosExpected =/= Tos).

check_range(Value, {Min, Max}) ->
    Value >= Min andalso Value =< Max.

base_port(Src, Dst) ->
    EphemeralRange = application:get_env(erlflow, ephemeral_range, ?DEFAULT_DYNAMIC_PORTS),
    Min = erlang:min(Src, Dst),
    case check_range(Min, EphemeralRange) of
        true -> 0;
        false -> Min
    end.

assemble_attributes(Attrs, ExtAttrs, FlowRec, SensorAddress) ->
    BaseAttrs = lists:foldl(fun
        ("src_addr", Acc) -> Acc#{src_addr => to_string_ip(FlowRec#nfrec_v5.src_addr)};
        ("dst_addr", Acc) -> Acc#{dst_addr => to_string_ip(FlowRec#nfrec_v5.dst_addr)};
        ("src_port", Acc) -> Acc#{src_port => FlowRec#nfrec_v5.src_port};
        ("dst_port", Acc) -> Acc#{src_port => FlowRec#nfrec_v5.dst_port};
        ("port", Acc) -> Acc#{port => base_port(FlowRec#nfrec_v5.src_port, FlowRec#nfrec_v5.dst_port)};
        ("proto", Acc) -> Acc#{proto => FlowRec#nfrec_v5.prot};
        ("tos", Acc) -> Acc#{tos => FlowRec#nfrec_v5.tos}
    end, #{}, Attrs),
    maps:merge(BaseAttrs#{sensor => to_string_ip(SensorAddress)}, maps:without(?ALL_ATTRS, ExtAttrs)).

to_binary_ip({Octet1, Octet2, Octet3, Octet4}) ->
    <<Octet1:8, Octet2:8, Octet3:8, Octet4:8>>;
to_binary_ip(RawData) when is_integer(RawData) ->
    <<RawData:32>>.

to_string_ip(Ip) when is_tuple(Ip)->
    inet:ntoa(Ip);
to_string_ip(Ip) when is_integer(Ip)->
    to_string_ip(<<Ip:32>>);
to_string_ip(RawData) ->
    <<Octet1:8, Octet2:8, Octet3:8, Octet4:8>> = RawData,
    O1 = integer_to_binary(Octet1),
    O2 = integer_to_binary(Octet2),
    O3 = integer_to_binary(Octet3),
    O4 = integer_to_binary(Octet4),
    unicode:characters_to_list(<<O1/bits,".",O2/bits,".",O3/bits,".",O4/bits>>).