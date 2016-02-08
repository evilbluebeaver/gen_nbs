%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2014. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
-module(gen_nbs).

%% API
-export([start/3, start/4,
         start_link/3, start_link/4,
         abcast/2, abcast/3,
         multimsg/3, multimsg/4, multimsg/5,
         stop/1, stop/3,
         cast/2, msg/3, msg/4,
         ack/2, fail/1,
         enter_loop/3, enter_loop/4, enter_loop/5, wake_hib/1]).

%% System exports
-export([system_continue/3,
         system_terminate/4,
         system_code_change/4,
         system_get_state/1,
         system_replace_state/2,
         format_status/2]).

%% Internal exports
-export([init_it/6]).


%%%=========================================================================
%%% Types specification
%%%=========================================================================
-type reg_name() :: {local, atom()} | {global, atom()} | {via, atom(), term()}.
-type dest() :: pid() | atom() | {atom(), atom()} | {global, atom()} | {via, atom(), term()}.
-type options() :: [atom() | tuple()].
-type start_result() :: {ok, pid()} | {error, term()} | {error, {already_started, pid()}}.
-type from() :: {pid(), reference()}.
-type await() :: {reference(), reference() | undefined, term()}.
-type callback_result() ::
    {ack, To :: from(), Ack :: term(), NewState :: term()} |
    {ack, To :: from(), Ack :: term(), NewState :: term(), timeout() | hibernate} |
    {await, Await :: {reference(), reference()}, NewState :: term()} |
    {await, Await :: {reference(), reference()}, NewState :: term(), timeout() | hibernate} |
    {ok, NewState :: term()} |
    {ok, NewState :: term(), timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
    {stop, Reason :: term(), NewState :: term()}.

%%%=========================================================================
%%%  Callback API
%%%=========================================================================

-callback init(Args :: term()) ->
    {ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
    {stop, Reason :: term()} | ignore.
-callback handle_msg(Message :: term(), From :: from(), State :: term()) ->
    callback_result().
-callback handle_ack(Ack :: term(), Tag :: term(), State :: term()) ->
    callback_result().
-callback handle_fail(Tag :: term(), State :: term()) ->
    callback_result().
-callback handle_info(Info :: timeout | term(), State :: term()) ->
    callback_result().
-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                    State :: term()) ->
    term().
-callback code_change(OldVsn :: (term() | {down, term()}), State :: term(),
                      Extra :: term()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.
-callback format_status(Opt, StatusData) -> Status when
      Opt :: 'normal' | 'terminate',
      StatusData :: [PDict | State],
      PDict :: [{Key :: term(), Value :: term()}],
      State :: term(),
      Status :: term().

-optional_callbacks([format_status/2]).

-define(FROM(What, Ref), {What, Ref}).
-define(AWAIT(Ref, Timer, Tag), {Ref, Timer, Tag}).

-define(ACK(Ref, Ack),  {'$gen_ack',    Ref, Ack}).
-define(CAST(Msg),      {'$gen_cast',   Msg}).
-define(MSG(From, Msg), {'$gen_msg',    From, Msg}).
-define(FAIL(Ref),      {'$gen_fail',   Ref}).

-define(OK_RET(State),      {ok, State}).
-define(TIMERS_RET(Timers), {timers, Timers}).
-define(ACK_RET(Tag),       {ack, Tag}).
-define(AWAIT_RET(Await),   {await, Await}).


%%%  -----------------------------------------------------------------
%%% Starts a generic server.
%%% start(Mod, Args, Options)
%%% start(Name, Mod, Args, Options)
%%% start_link(Mod, Args, Options)
%%% start_link(Name, Mod, Args, Options) where:
%%%    Name ::= {local, atom()} | {global, atom()} | {via, atom(), term()}
%%%    Mod  ::= atom(), callback module implementing the 'real' server
%%%    Args ::= term(), init arguments (to Mod:init/1)
%%%    Options ::= [{timeout, Timeout} | {debug, [Flag]}]
%%%      Flag ::= trace | log | {logfile, File} | statistics | debug
%%%          (debug == log && statistics)
%%% Returns: {ok, Pid} |
%%%          {error, {already_started, Pid}} |
%%%          {error, Reason}
%%% -----------------------------------------------------------------

-spec start(Mod :: atom(), Args :: term(), Options :: options()) -> start_result().
start(Mod, Args, Options) ->
    gen:start(?MODULE, nolink, Mod, Args, Options).

-spec start(Name :: reg_name(), Mod :: atom(), Args :: term(), Options :: options()) -> start_result().
start(Name, Mod, Args, Options) ->
    gen:start(?MODULE, nolink, Name, Mod, Args, Options).

-spec start_link(Mod :: atom(), Args :: term(), Options :: options()) -> start_result().
start_link(Mod, Args, Options) ->
    gen:start(?MODULE, link, Mod, Args, Options).

-spec start_link(Name :: reg_name(), Mod :: atom(), Args :: term(), Options :: options()) -> start_result().
start_link(Name, Mod, Args, Options) ->
    gen:start(?MODULE, link, Name, Mod, Args, Options).


%% -----------------------------------------------------------------
%% Stop a generic server and wait for it to terminate.
%% If the server is located at another node, that node will
%% be monitored.
%% -----------------------------------------------------------------
-spec stop(Name :: dest()) -> term().
stop(Name) ->
    gen:stop(Name).

-spec stop(Name :: dest(), Reason :: term(), Timeout :: timeout()) -> term().
stop(Name, Reason, Timeout) ->
    gen:stop(Name, Reason, Timeout).

%% -----------------------------------------------------------------
%% Make a cast to to a generic server.
%% -----------------------------------------------------------------

-spec cast(Dest :: dest(), Msg :: term()) -> ok.
cast(Dest, Msg) ->
    do_send(Dest, cast, Msg).

%% -----------------------------------------------------------------
%% Post a message to a generic server.
%% -----------------------------------------------------------------

-spec msg(Dest :: dest(), Msg :: term(), Tag :: term()) -> await().
msg(Dest, Msg, Tag) ->
    msg(Dest, Msg, Tag, 5000).
-spec msg(Dest :: dest(), Msg :: term(), Tag :: term(), Timeout :: timeout()) -> await().
msg(Dest, Msg, Tag, Timeout) ->
    do_send(Dest, msg, {Msg, Tag}, Timeout).

%% -----------------------------------------------------------------
%% Manual ack/fail
%% -----------------------------------------------------------------

-spec ack(From :: from(), Ack :: term()) -> ok.
ack(?FROM(From, Ref), Ack) ->
    From ! ?ACK(Ref, Ack),
    ok.

-spec fail(From :: from()) -> ok.
fail(?FROM(From, Ref)) ->
    From ! ?FAIL(Ref),
    ok.

%% -----------------------------------------------------------------
%% Asynchronous broadcast, returns nothing, it's just send 'n' pray
%%------------------------------------------------------------------
-spec abcast(Name :: dest(), Msg :: term()) -> abcast.
abcast(Name, Msg) when is_atom(Name) ->
    do_abcast([node() | nodes()], Name, Msg).

-spec abcast(Nodes :: [atom()], Name :: atom(), Msg :: term()) -> abcast.
abcast(Nodes, Name, Msg) when is_list(Nodes), is_atom(Name) ->
    do_abcast(Nodes, Name, Msg).


-spec multimsg(Name :: dest(), Msg :: term(), Tag :: term()) -> [await()].
multimsg(Name, Msg, Tag) when is_atom(Name) ->
    do_multimsg([node() | nodes()], Name, msg, {Msg, Tag}).

-spec multimsg(Name :: dest(), Msg :: term(), Tag :: term(), Timeout :: timeout()) -> [await()];
              (Nodes :: [atom()], Name :: atom(), Msg :: term(), Tag :: term()) -> [await()].
multimsg(Nodes, Name, Msg, Tag) when is_list(Nodes), is_atom(Name) ->
    do_multimsg(Nodes, Name, msg, {Msg, Tag});

multimsg(Name, Msg, Tag, Timeout) when is_atom(Name) ->
    do_multimsg([node() | nodes()], Name, msg, {Msg, Tag}, Timeout).

-spec multimsg(Nodes :: [atom()], Name :: atom(), Msg :: term(), Tag :: term(), Timeout :: timeout()) -> [await()].
multimsg(Nodes, Name, Msg, Tag, Timeout) when is_list(Nodes), is_atom(Name) ->
    do_multimsg(Nodes, Name, msg, {Msg, Tag}, Timeout).

do_abcast(Nodes, Name, Msg) ->
    do_multimsg(Nodes, Name, cast, Msg),
    abcast.

do_multimsg(Nodes, Name, Type, Msg) ->
    do_multimsg(Nodes, Name, Type, Msg, 5000).
do_multimsg(Nodes, Name, Type, Msg, Timeout) ->
    do_multimsg(Nodes, Name, Type, Msg, Timeout, []).
do_multimsg([Node|Nodes], Name, Type, Msg, Timeout, Result) when is_atom(Node) ->
    R = do_send({Name,Node}, Type, Msg, Timeout),
    do_multimsg(Nodes, Name, Type, Msg, Timeout, [R | Result]);
do_multimsg([], _, _, _, _, Result) -> Result.

%% -----------------------------------------------------------------
%% Send functions
%% -----------------------------------------------------------------
%%

-spec do_send(Dest :: dest(), cast, Msg :: term()) -> ok.
do_send(Dest, cast, Msg) ->
    do_cmd_send(Dest, ?CAST(Msg)).

-spec do_send(Dest :: dest(), cast, Msg :: term(), Timeout :: timeout()) -> await();
             (Dest :: dest(), msg,  Msg :: {term(), term()}, Timeout :: timeout()) -> await().
do_send(Dest, cast, Msg, _) ->
    do_cmd_send(Dest, ?CAST(Msg));
do_send(Dest, msg, {Msg, Tag}, Timeout) ->
    SName = monitor_suitable_name(Dest),
    Ref = monitor(process, SName),
    TimerRef = case Timeout of
                   infinity ->
                       undefined;
                   T ->
                       erlang:send_after(T, self(), ?FAIL(Ref))
               end,
    From = ?FROM(self(), Ref),
    do_cmd_send(Dest, ?MSG(From, Msg)),
    ?AWAIT(Ref, TimerRef, Tag).

monitor_suitable_name(Pid) when is_pid(Pid) ->
    Pid;
monitor_suitable_name(Name) when is_atom(Name) ->
    Name;
monitor_suitable_name({global, Name}) ->
    global:whereis_name(Name);
monitor_suitable_name({via, Mod, Name}) ->
    Mod:whereis_name(Name);
monitor_suitable_name({Dest, Node}=FullName) when is_atom(Dest), is_atom(Node) ->
    FullName.

do_cmd_send({global, Name}, Cmd) ->
    catch global:send(Name, Cmd);
do_cmd_send({via, Mod, Name}, Cmd) ->
    catch Mod:send(Name, Cmd);
do_cmd_send({Name, Node}=Dest, Cmd) when is_atom(Name), is_atom(Node) ->
    do_cmd_default_send(Dest, Cmd);
do_cmd_send(Dest, Cmd) when is_atom(Dest) ->
    do_cmd_default_send(Dest, Cmd);
do_cmd_send(Dest, Cmd) when is_pid(Dest) ->
    do_cmd_default_send(Dest, Cmd).

do_cmd_default_send(Dest, Cmd) ->
    case catch erlang:send(Dest, Cmd, [noconnect]) of
        noconnect ->
            spawn(erlang, send, [Dest, Cmd]);
        Other ->
            Other
    end,
    ok.

-record(inner_state, {parent,
                      name,
                      state,
                      mod,
                      timeout,
                      debug,
                      timers=#{}}).

%%-----------------------------------------------------------------
%% enter_loop(Mod, Options, State, <ServerName>, <TimeOut>) ->_
%%
%% Description: Makes an existing process into a gen_nbs.
%%              The calling process will enter the gen_nbs receive
%%              loop and become a gen_nbs process.
%%              The process *must* have been started using one of the
%%              start functions in proc_lib, see proc_lib(3).
%%              The user is responsible for any initialization of the
%%              process, including registering a name for it.
%%-----------------------------------------------------------------
enter_loop(Mod, Options, State) ->
    enter_loop(Mod, Options, State, self(), infinity).

enter_loop(Mod, Options, State, ServerName = {Scope, _})
  when Scope == local; Scope == global ->
    enter_loop(Mod, Options, State, ServerName, infinity);

enter_loop(Mod, Options, State, ServerName = {via, _, _}) ->
    enter_loop(Mod, Options, State, ServerName, infinity);

enter_loop(Mod, Options, State, Timeout) ->
    enter_loop(Mod, Options, State, self(), Timeout).

enter_loop(Mod, Options, State, ServerName, Timeout) ->
    Name = get_proc_name(ServerName),
    Parent = get_parent(),
    Debug = debug_options(Name, Options),
    InnerState = #inner_state{parent=Parent,
                              name=Name,
                              state=State,
                              mod=Mod,
                              timeout=Timeout,
                              debug=Debug},
    loop(InnerState).

%%%========================================================================
%%% Gen-callback functions
%%%========================================================================

%%% ---------------------------------------------------
%%% Initiate the new process.
%%% Register the name using the Rfunc function
%%% Calls the Mod:init/Args function.
%%% Finally an acknowledge is sent to Parent and the main
%%% loop is entered.
%%% ---------------------------------------------------
init_it(Starter, self, Name, Mod, Args, Options) ->
    init_it(Starter, self(), Name, Mod, Args, Options);
init_it(Starter, Parent, Name0, Mod, Args, Options) ->
    Name = name(Name0),
    Debug = debug_options(Name, Options),
    InnerState = #inner_state{parent=Parent,
                              name=Name,
                              mod=Mod,
                              debug=Debug},
    case catch Mod:init(Args) of
        {ok, State} ->
            proc_lib:init_ack(Starter, {ok, self()}),
            loop(InnerState#inner_state{state=State, timeout=infinity});
        {ok, State, Timeout} ->
            proc_lib:init_ack(Starter, {ok, self()}),
            loop(InnerState#inner_state{state=State, timeout=Timeout});
        {stop, Reason} ->
            %% For consistency, we must make sure that the
            %% registered name (if any) is unregistered before
            %% the parent process is notified about the failure.
            %% (Otherwise, the parent process could get
            %% an 'already_started' error if it immediately
            %% tried starting the process again.)
            unregister_name(Name0),
            proc_lib:init_ack(Starter, {error, Reason}),
            exit(Reason);
        ignore ->
            unregister_name(Name0),
            proc_lib:init_ack(Starter, ignore),
            exit(normal);
        {'EXIT', Reason} ->
            unregister_name(Name0),
            proc_lib:init_ack(Starter, {error, Reason}),
            exit(Reason);
        Else ->
            Error = {bad_return_value, Else},
            proc_lib:init_ack(Starter, {error, Error}),
            exit(Error)
    end.

name({local,Name}) -> Name;
name({global,Name}) -> Name;
name({via,_, Name}) -> Name;
name(Pid) when is_pid(Pid) -> Pid.

unregister_name({local,Name}) ->
    _ = (catch unregister(Name));
unregister_name({global,Name}) ->
    _ = global:unregister_name(Name);
unregister_name({via, Mod, Name}) ->
    _ = Mod:unregister_name(Name);
unregister_name(Pid) when is_pid(Pid) ->
    Pid.

%%%========================================================================
%%% Internal functions
%%%========================================================================
%%% ---------------------------------------------------
%%% The MAIN loop.
%%% ---------------------------------------------------
loop(InnerState=#inner_state{timeout=hibernate}) ->
    proc_lib:hibernate(?MODULE, wake_hib, [InnerState]);
loop(InnerState=#inner_state{timeout=Timeout}) ->
    Msg = receive
              Input ->
                  Input
          after Timeout ->
                    timeout
          end,
    decode_msg(Msg, InnerState).

wake_hib(InnerState) ->
    Msg = receive
              Input ->
                  Input
          end,
    decode_msg(Msg, InnerState).

decode_msg(Msg, InnerState=#inner_state{parent=Parent,
                                        name=Name,
                                        debug=Debug,
                                        timeout=Timeout}) ->
    case Msg of
        {system, From, Req} ->
            sys:handle_system_msg(Req, From, Parent, ?MODULE, Debug,
                                  InnerState, Timeout==hibernate);
        {'EXIT', Parent, Reason} ->
            terminate(Reason, Msg, InnerState);
        _Msg when Debug =:= [] ->
            handle_msg(Msg, InnerState);
        _Msg ->
            Debug1 = sys:handle_debug(Debug, fun print_event/3,
                                      Name, Msg),
            handle_msg(Msg, InnerState#inner_state{debug=Debug1})
    end.

%% ---------------------------------------------------
%% Helper functions for try-catch of callbacks.
%% Returns the return value of the callback, or
%% {'EXIT', ExitReason, ReportReason} (if an exception occurs)
%%
%% ExitReason is the reason that shall be used when the process
%% terminates.
%%
%% ReportReason is the reason that shall be printed in the error
%% report.
%% ---------------------------------------------------

try_dispatch({'DOWN', Ref, process, _Pid, _Info}, Mod, State, Timers) ->
    try_dispatch(?FAIL(Ref), Mod, State, Timers);
try_dispatch(?CAST(Msg), Mod, State, _Timers) ->
    try_handle(Mod, handle_cast, [Msg, State]);
try_dispatch(?MSG(From, Msg), Mod, State, _Timers) ->
    try_handle(Mod, handle_msg, [Msg, From, State]);
try_dispatch(?FAIL(Ref), Mod, State, Timers) ->
    true = demonitor(Ref),
    case maps:find(Ref, Timers) of
        error ->
            {ok, {ok, State}};
        {ok, {Timer, Tag}} ->
            NTimers = maps:remove(Ref, Timers),
            case Timer of
                undefined ->
                    ok;
                _ ->
                    erlang:cancel_timer(Timer)
            end,
            try_handle(Mod, handle_fail, [Tag, State], NTimers)
    end;
try_dispatch(?ACK(Ref, Ack), Mod, State, Timers) ->
    true = demonitor(Ref),
    case maps:find(Ref, Timers) of
        error ->
            {ok, {ok, State}};
        {ok, {Timer, Tag}} ->
            NTimers = maps:remove(Ref, Timers),
            case Timer of
                undefined ->
                    ok;
                _ ->
                    erlang:cancel_timer(Timer)
            end,
            try_handle(Mod, handle_ack, [Ack, Tag, State], NTimers)
    end;
try_dispatch(Info, Mod, State, _Timers) ->
    try_handle(Mod, handle_info, [Info, State]).

try_handle(Mod, Func, Args) ->
    try_handle(Mod, Func, Args, undefined).

try_handle(Mod, Func, Args, Timers) ->
   try
        Reply = erlang:apply(Mod, Func, Args),
        case Timers of
            undefined ->
                {ok, Reply};
            T ->
                {timers, T, {ok, Reply}}
        end
    catch
        throw:R ->
            {ok, R};
        error:R ->
            Stacktrace = erlang:get_stacktrace(),
            {'EXIT', {R, Stacktrace}, {R, Stacktrace}};
        exit:R ->
            Stacktrace = erlang:get_stacktrace(),
            {'EXIT', R, {R, Stacktrace}}
    end.

try_terminate(Mod, Reason, State) ->
    try
        {ok, Mod:terminate(Reason, State)}
    catch
        throw:R ->
            {ok, R};
        error:R ->
            Stacktrace = erlang:get_stacktrace(),
            {'EXIT', {R, Stacktrace}, {R, Stacktrace}};
        exit:R ->
            Stacktrace = erlang:get_stacktrace(),
            {'EXIT', R, {R, Stacktrace}}
    end.

%%% ---------------------------------------------------
%%% Message handling functions
%%% ---------------------------------------------------

handle_msg(Msg, InnerState=#inner_state{mod=Mod, state=State, timers=Timers}) ->
    Reply = try_dispatch(Msg, Mod, State, Timers),
    handle_common_reply(Reply, Msg, InnerState).

handle_common_reply(Reply, Msg, InnerState=#inner_state{timers=Timers}) ->
    case Reply of
        {ok, {await, Await, NState}} ->
            NTimers = update_timers(Await, Timers),
            NInnerState = debug(?AWAIT_RET(Await),
                                InnerState#inner_state{state=NState, timers=NTimers}),
            loop(NInnerState#inner_state{timeout=infinity});
        {ok, {await, Await, NState, Time}} ->
            NTimers = update_timers(Await, Timers),
            NInnerState = debug(?AWAIT_RET(Await),
                                InnerState#inner_state{state=NState, timers=NTimers}),
            loop(NInnerState#inner_state{timeout=Time});
        {ok, {ack, ?FROM(From, Ref)=Tag, Ack, NState}} ->
            From ! ?ACK(Ref, Ack),
            NInnerState = debug(?ACK_RET(Tag),
                                InnerState#inner_state{state=NState}),
            loop(NInnerState#inner_state{timeout=infinity});
        {ok, {ack, ?FROM(From, Ref)=Tag, Ack, NState, Time}} ->
            From ! ?ACK(Ref, Ack),
            NInnerState = debug(?ACK_RET(Tag),
                                InnerState#inner_state{state=NState}),
            loop(NInnerState#inner_state{timeout=Time});
        {timers, NTimers, NReply} ->
            NInnerState = debug(?TIMERS_RET(NTimers),
                                InnerState#inner_state{timers=NTimers}),
            handle_common_reply(NReply, Msg, NInnerState);
        {ok, {ok, NState}} ->
            NInnerState = debug(?OK_RET(NState),
                                InnerState#inner_state{state=NState}),
            loop(NInnerState#inner_state{timeout=infinity});
        {ok, {ok, NState, Time}} ->
            NInnerState = debug(?OK_RET(NState),
                                InnerState#inner_state{state=NState}),
            loop(NInnerState#inner_state{timeout=Time});
        {ok, {stop, Reason, NState}} ->
            terminate(Reason, Msg, InnerState#inner_state{state=NState});
        {'EXIT', ExitReason, ReportReason} ->
            terminate(ExitReason, ReportReason, InnerState);
        {ok, BadReply} ->
            terminate({bad_return_value, BadReply}, Msg, InnerState)
    end.

update_timers([], Timers) ->
    Timers;
update_timers(Await, Timers) when is_list(Await) ->
    lists:foldl(fun update_timers/2, Timers, Await);
update_timers(?AWAIT(Ref, Timer, Tag), Timers) ->
    maps:put(Ref, {Timer, Tag}, Timers).


%%-----------------------------------------------------------------
%% Callback functions for system messages handling.
%%-----------------------------------------------------------------
system_continue(Parent, Debug, InnerState) ->
    loop(InnerState#inner_state{debug=Debug, parent=Parent}).

-spec system_terminate(_, _, _, [_]) -> no_return().

system_terminate(Reason, _Parent, Debug, InnerState) ->
    terminate(Reason, [], InnerState#inner_state{debug=Debug}).

system_code_change(InnerState=#inner_state{mod=Mod, state=State}, _Module, OldVsn, Extra) ->
    case catch Mod:code_change(OldVsn, State, Extra) of
        {ok, NewState} -> {ok, InnerState#inner_state{state=NewState}};
        Else -> Else
    end.

system_get_state(#inner_state{state=State}) ->
    {ok, State}.

system_replace_state(StateFun, InnerState=#inner_state{state=State}) ->
    NState = StateFun(State),
    {ok, NState, InnerState#inner_state{state=NState}}.

%%% ---------------------------------------------------
%%% Debug functions
%%% ---------------------------------------------------

debug(_Msg, InnerState=#inner_state{debug=[]}) ->
    InnerState;

debug(Msg, InnerState=#inner_state{name=Name,
                                   debug=Debug}) ->
    Debug1 = sys:handle_debug(Debug, fun print_event/3, Name,
                              Msg),
    InnerState#inner_state{debug=Debug1}.

%%-----------------------------------------------------------------
%% Format debug messages.  Print them as the call-back module sees
%% them, not as the real erlang messages.  Use trace for that.
%%-----------------------------------------------------------------
print_event(Dev, ?CAST(Msg), Name) ->
    io:format(Dev, "*DBG* ~p got cast ~p~n",
              [Name, Msg]);
print_event(Dev, ?ACK(Ref, Ack), Name) ->
    io:format(Dev, "*DBG* ~p got acknowledgement ~p from ~p~n",
              [Name, Ack, Ref]);
print_event(Dev, ?FAIL(Ref), Name) ->
    io:format(Dev, "*DBG* ~p message to ~p timed out~n",
              [Name, Ref]);
print_event(Dev, ?MSG(Tag, Msg), Name) ->
    io:format(Dev, "*DBG* ~p got msg ~p from ~p~n",
              [Name, Msg, Tag]);
print_event(Dev, ?OK_RET(State), Name) ->
    io:format(Dev, "*DBG* ~p new state ~p~n", [Name, State]);
print_event(Dev, ?TIMERS_RET(Timers), Name) ->
    io:format(Dev, "*DBG* ~p new timers ~p~n", [Name, Timers]);
print_event(Dev, ?ACK_RET(Tag), Name) ->
    io:format(Dev, "*DBG* ~p sent acknowledgement to ~p~n", [Name, Tag]);
print_event(Dev, ?AWAIT_RET(Await), Name) ->
    io:format(Dev, "*DBG* ~p  await for ~p~n", [Name, Await]);
print_event(Dev, Msg, Name) ->
    io:format(Dev, "*DBG* ~p got ~p~n", [Name, Msg]).



%%% ---------------------------------------------------
%%% Terminate the server.
%%% ---------------------------------------------------

-spec terminate(_, _, _) -> no_return().
terminate(Reason, Msg, InnerState) ->
    terminate(Reason, Reason, Msg, InnerState).

-spec terminate(_, _, _, _) -> no_return().
terminate(ExitReason, ReportReason, Msg, #inner_state{mod=Mod,
                                                      state=State,
                                                      name=Name,
                                                      debug=Debug}) ->
    Reply = try_terminate(Mod, ExitReason, State),
    case Reply of
        {'EXIT', ExitReason1, ReportReason1} ->
            FmtState = format_status(terminate, Mod, get(), State),
            error_info(ReportReason1, Name, Msg, FmtState, Debug),
            exit(ExitReason1);
        _ ->
            case ExitReason of
                normal ->
                    exit(normal);
                shutdown ->
                    exit(shutdown);
                {shutdown,_}=Shutdown ->
                    exit(Shutdown);
                _ ->
                    FmtState = format_status(terminate, Mod, get(), State),
                    error_info(ReportReason, Name, Msg, FmtState, Debug),
                    exit(ExitReason)
            end
    end.

error_info(Reason, Name, Msg, State, Debug) ->
    error_logger:format("** Generic server ~p terminating \n"
                        "** Last message in was ~p~n"
                        "** When Server state == ~p~n"
                        "** Reason for termination == ~n** ~p~n",
                        [Name, Msg, State, Reason]),
    sys:print_log(Debug),
    ok.

%%% ---------------------------------------------------
%%% Misc. functions.
%%% ---------------------------------------------------

debug_options(Name, Opts) ->
    case proplists:get_value(debug, Opts) of
        undefined ->
            [];
        Options ->
            dbg_opts(Name, Options)
    end.

dbg_opts(Name, Opts) ->
    case catch sys:debug_options(Opts) of
        {'EXIT',_} ->
            error_logger:format("~p: ignoring erroneous debug options - ~p~n",
                                [Name, Opts]),
            [];
        Dbg ->
            Dbg
    end.

get_proc_name(Pid) when is_pid(Pid) ->
    Pid;
get_proc_name({local, Name}) ->
    case process_info(self(), registered_name) of
        {registered_name, Name} ->
            Name;
        {registered_name, _Name} ->
            exit(process_not_registered);
        [] ->
            exit(process_not_registered)
    end;
get_proc_name({global, Name}) ->
    case global:whereis_name(Name) of
        undefined ->
            exit(process_not_registered_globally);
        Pid when Pid =:= self() ->
            Name;
        _Pid ->
            exit(process_not_registered_globally)
    end;
get_proc_name({via, Mod, Name}) ->
    case Mod:whereis_name(Name) of
        undefined ->
            exit({process_not_registered_via, Mod});
        Pid when Pid =:= self() ->
            Name;
        _Pid ->
            exit({process_not_registered_via, Mod})
    end.

get_parent() ->
    case get('$ancestors') of
        [Parent | _] when is_pid(Parent)->
            Parent;
        [Parent | _] when is_atom(Parent)->
            name_to_pid(Parent);
        _ ->
            exit(process_was_not_started_by_proc_lib)
    end.

name_to_pid(Name) ->
    case whereis(Name) of
        undefined ->
            exit(could_not_find_registered_name);
        Pid ->
            Pid
    end.

%%-----------------------------------------------------------------
%% Status information
%%-----------------------------------------------------------------
format_status(Opt, StatusData) ->
    [PDict, SysState, Parent, Debug, #inner_state{name=Name, mod=Mod, state=State}] = StatusData,
    Header = gen:format_status_header("Status for generic server", Name),
    Log = sys:get_debug(log, Debug, []),
    Specfic = format_status(Opt, Mod, PDict, State),
    [{header, Header},
     {data, [{"Status", SysState},
             {"Parent", Parent},
             {"Logged events", Log}]} |
     Specfic].

format_status(Opt, Mod, PDict, State) ->
    DefStatus = case Opt of
                    terminate -> State;
                    _ -> [{data, [{"State", State}]}]
                end,
    case erlang:function_exported(Mod, format_status, 2) of
        true ->
            case catch Mod:format_status(Opt, [PDict, State]) of
                {'EXIT', _} -> DefStatus;
                L when is_list(L) -> L;
                Else -> [Else]
            end;
        _ ->
            DefStatus
    end.
