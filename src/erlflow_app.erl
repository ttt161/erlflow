%%%-------------------------------------------------------------------
%% @doc erlflow public API
%% @end
%%%-------------------------------------------------------------------

-module(erlflow_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    erlflow_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
