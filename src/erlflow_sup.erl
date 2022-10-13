%%%-------------------------------------------------------------------
%% @doc erlflow top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(erlflow_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1, start_listener/0]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 0,
                 period => 1},
    VectorSup = #{
        id => collector_sup,
        start => {erlflow_collector_sup, start_link, []},
        type => supervisor
    },
    RegSpec = #{
        id => erlflow_register,
        start => {erlflow_register, start_link, []}
    },
    MainSpec = #{
        id => erlflow,
        start => {erlflow, start_link, []}
    },
    HttpSpec = #{
        id => listener,
        start => {?MODULE, start_listener, []}
    },
    ChildSpecs = [RegSpec, VectorSup, MainSpec, HttpSpec],
    {ok, {SupFlags, ChildSpecs}}.

start_listener() ->
    IP = application:get_env(erlflow, http_ip, {0,0,0,0}),
    Port = application:get_env(erlflow, http_port, 9101),
    Routes = [
        {"/metrics", erlflow_http_handler, #{}}
    ],
    Args = [
        {ip, IP},
        {port, Port}
    ],
    RouteDispatch = cowboy_router:compile([{'_', Routes}]),
    Opts = #{
        env => #{
            dispatch => RouteDispatch
        },
        middlewares => [
            cowboy_router,
            cowboy_handler
        ]
    },
    cowboy:start_clear(http, Args, Opts).

%% internal functions
