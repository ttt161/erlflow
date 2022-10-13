-module(erlflow_http_handler).
-behaviour(cowboy_rest).

-record(state, {}).

-export([
    init/2,
    process/2,
    allowed_methods/2,
    content_types_provided/2
]).

init(Req, _Opts) ->
    {cowboy_rest, Req, #state{}}.

allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.

content_types_provided(Req, State) ->
    {[
        {{<<"text">>, <<"html">>, []}, process}
    ], Req, State}.

process(Req, State) ->
    Data = erlflow_collector:collect(),
    Req1 = cowboy_req:reply(200, #{<<"content-type">> => <<"text/html">>}, unicode:characters_to_list(Data), Req),
    {stop, Req1, State}.
