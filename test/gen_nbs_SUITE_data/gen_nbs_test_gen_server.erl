-module(gen_nbs_test_gen_server).

-behaviour(gen_server).

%% API
-export([start_link/0,
         start/0,
         stop/1,
         normal_call/1,
         timeout_call/1,
         exit_call/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

normal_call(Pid) ->
    gen_server:call(Pid, normal).

timeout_call(Pid) ->
    gen_server:call(Pid, timeout, 0).

exit_call(Pid) ->
    gen_server:call(Pid, exit).

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link(?MODULE, [], []).

start() ->
    gen_server:start(?MODULE, [], []).

stop(Pid) ->
    gen_server:stop(Pid).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([]) ->
    {ok, #{}}.

handle_call(normal, _From, State) ->
    {reply, ok, State};

handle_call(timeout, _From, State) ->
    timer:sleep(100),
    {reply, ok, State};

handle_call(exit, _From, State) ->
    {stop, normal, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
