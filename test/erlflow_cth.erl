-module(erlflow_cth).
-include_lib("common_test/include/ct.hrl").

%% API
-export([init/2, terminate/1, pre_init_per_suite/3]).

init(_Id, State) ->
    application:load(erlflow),
    Priv = code:priv_dir(erlflow),
    Path = filename:join([Priv, "test.yml"]),

    application:set_env(erlflow, config_path, Path),
    application:ensure_all_started(erlflow),
    State.

pre_init_per_suite(_SuiteName, Config, State) ->
    {Config ++ State, State}.

terminate(_State) -> ok.
