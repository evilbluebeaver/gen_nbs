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
         stop/1, stop/3,
         return/1, return/2, msg/2, msg/3, package/1, package/2,
         transmit/2, transmit/3,
         safe_call/1, safe_call/3,
         cast/2,
         await/1, await/2,
         ack/2, fail/2,
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

-define(DEFAULT_TIMEOUT, 5000).

-include("gen_nbs_await.hrl").

%%%=========================================================================
%%% Types specification
%%%=========================================================================
-type reg_name() :: {local, atom()} | {global, atom()} | {via, atom(), term()}.
-type dest() :: pid() | atom() | {atom(), atom()} | {global, atom()} | {via, atom(), term()}.
-type options() :: [atom() | tuple()].
-type from() :: {pid(), reference()}.

-record(inner_state, {parent, name, state, mod, timeout, refs, debug}).

%-type result_r() :: {ack, term()} | {fail, term()}.
%-type result() :: result_r() | [result_r()].
-type callback_result() ::
{fail, To :: from(), Reason :: term(), NewState :: term()} |
{fail, To :: from(), Reason :: term(), NewState :: term(), timeout()} |
{ack, To :: from(), Ack :: term(), NewState :: term()} |
{ack, To :: from(), Ack :: term(), NewState :: term(), timeout() | hibernate} |
{await, Await :: await(), NewState :: term()} |
{await, Await :: await(), NewState :: term(), timeout() | hibernate} |
{ok, NewState :: term()} |
{ok, NewState :: term(), timeout() | hibernate} |
{stop, Reason :: term(), NewState :: term()}.

-export_type([await/0, msg/0]).
%%%=========================================================================
%%%  Callback API
%%%=========================================================================

-callback init(Args :: term()) ->
    {ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
    {stop, Reason :: term()} | ignore.
-callback handle_msg(Message :: term(), From :: from(), State :: term()) ->
    callback_result().
-callback handle_ack({ack, Ack :: term()} | {fail, Reason :: term()}, Tag :: term(), State :: term()) ->
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

-define(RES(Ref, Result, Ack),  {'$gen_ack', Result, Ref, Ack}).
-define(ACK(Ref, Ack),      ?RES(Ref, ack, Ack)).
-define(FAIL(Ref, Reason),      ?RES(Ref, fail, Reason)).

-define(CAST(Msg),        {'$gen_cast', Msg}).
-define(MSG(From, Msg),   {'$gen_msg',  From, Msg}).

-define(OK_RET(State),      {ok, State}).
-define(ACK_RET(Tag),       {ack, Tag}).
-define(FAIL_RET(Tag),      {fail, Tag}).
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

-spec start(Mod :: atom(), Args :: term(), Options :: options()) ->
    {ok, pid()} | {error, term()}.
start(Mod, Args, Options) ->
    gen:start(?MODULE, nolink, Mod, Args, Options).

-spec start(Name :: reg_name(), Mod :: atom(), Args :: term(), Options :: options()) ->
    {ok, pid()} | {error, term()}.
start(Name, Mod, Args, Options) ->
    gen:start(?MODULE, nolink, Name, Mod, Args, Options).

-spec start_link(Mod :: atom(), Args :: term(), Options :: options()) ->
    {ok, pid()} | {error, term()}.
start_link(Mod, Args, Options) ->
    gen:start(?MODULE, link, Mod, Args, Options).

-spec start_link(Name :: reg_name(), Mod :: atom(), Args :: term(), Options :: options()) ->
    {ok, pid()} | {error, term()}.
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
    do_send(Dest, ?CAST(Msg)).

%% -----------------------------------------------------------------
%% Create a message to a generic server.
%% -----------------------------------------------------------------

-spec return(Payload :: term()) -> msg().
return(Payload) ->
    #return{payload=Payload}.

-spec return(Payload :: term(),
             CompletionFun :: completion_fun()) -> msg().
return(Payload, CompletionFun) when CompletionFun == undefined ->
    #return{payload=Payload, completion_fun=CompletionFun};
return(Payload, CompletionFun) when is_function(CompletionFun) ->
    #return{payload=Payload, completion_fun=CompletionFun}.

-spec msg(Dest :: dest(), Payload :: term()) -> msg().
msg(Dest, Payload) ->
    #msg{dest=Dest, payload=Payload}.

-spec msg(Dest :: dest(), Payload :: term(),
          CompletionFun :: completion_fun()) -> msg().
msg(Dest, Payload, CompletionFun) when CompletionFun == undefined ->
    #msg{dest=Dest, payload=Payload, completion_fun=CompletionFun};
msg(Dest, Payload, CompletionFun) when is_function(CompletionFun) ->
    #msg{dest=Dest, payload=Payload, completion_fun=CompletionFun}.

-spec package(Msgs :: #{term() => msg()}) -> msg().
package(Msgs) when is_map(Msgs) ->
    #package{children=Msgs}.

-spec package(Msgs :: #{term() => msg()},
              CompletionFun :: completion_fun()) -> msg().
package(Msgs, CompletionFun) when is_map(Msgs), CompletionFun == undefined->
    #package{children=Msgs, completion_fun=CompletionFun};

package(Msgs, CompletionFun) when is_map(Msgs), is_function(CompletionFun)->
    #package{children=Msgs, completion_fun=CompletionFun}.

%% -----------------------------------------------------------------
%% Transmit created messages
%% -----------------------------------------------------------------

-spec transmit(Msgs :: msg(), Tag :: term()) -> await().
transmit(Msgs, Tag) ->
    transmit(Msgs, Tag, ?DEFAULT_TIMEOUT).

-spec transmit(Msgs :: msg(), Tag :: term(), Timeout :: timeout()) -> await().
transmit(Msg, Tag, Timeout) ->
    Ref = do_transmit(Msg),
    TimerRef = erlang:send_after(Timeout, self(), ?FAIL(Ref#ref.ref, timeout)),
    #await{tag=Tag,
           ref=Ref,
           timer_ref=TimerRef}.

do_transmit(_, Msg) ->
    do_transmit(Msg).

do_transmit(Msgs) when is_map(Msgs) ->
    do_transmit(#package{children=Msgs});

do_transmit(#package{children=Children,
                     completion_fun=CompletionFun}) ->
    #ref{ref=make_ref(),
         completion_fun=CompletionFun,
         children=maps:map(fun do_transmit/2, Children)};

do_transmit(#msg{dest=Dest, payload=Payload,
                 completion_fun=CompletionFun}) ->
    Name = monitor_suitable_name(Dest),
    Ref = monitor(process, Name),
    From = ?FROM(self(), Ref),
    do_send(Name, ?MSG(From, Payload)),
    #ref{ref=Ref, completion_fun=CompletionFun};

do_transmit(#return{payload=Payload,
                    completion_fun=CompletionFun}) ->
    Ref = make_ref(),
    case Payload of
        {ack, Data} ->
            erlang:send(self(), ?ACK(Ref, Data));
        {fail, Reason} ->
            erlang:send(self(), ?FAIL(Ref, Reason))
    end,
    #ref{ref=Ref, completion_fun=CompletionFun}.

%% -----------------------------------------------------------------
%% Executes gen_nbs's call safely. Prevent from getting of excess messages in case of
%% gen_nbs timeout or fail.
%% -----------------------------------------------------------------

-spec safe_call(Module :: atom(),
                Fun :: atom(),
                Args :: [term()]) ->
    term().
safe_call(Module, Fun, Args) ->
    safe_call(fun() -> erlang:apply(Module, Fun, Args) end).

-spec safe_call(Fun :: fun(() -> term())) ->
    term().
safe_call(Fun) ->
    Self = self(),
    Pid = spawn(fun() ->
                        Result = Fun(),
                        Self ! {result, Result}
                end),
    Ref = erlang:monitor(process, Pid),
    receive
        {result, Result} ->
            true = erlang:demonitor(Ref, [flush]),
            Result;
        {'DOWN', Ref, process, Pid, Reason} when Reason /= normal ->
            exit(Reason)
    end.

%% -----------------------------------------------------------------
%% Manual ack/fail
%% -----------------------------------------------------------------

-spec ack(From :: from(), Ack :: term()) -> ok.
ack(?FROM(From, Ref), Ack) ->
    From ! ?ACK(Ref, Ack),
    ok.

-spec fail(From :: from(), Reason :: term()) -> ok.
fail(?FROM(From, Ref), Reason) ->
    From ! ?FAIL(Ref, Reason),
    ok.

%% -----------------------------------------------------------------
%% Expects the results without having to implement a gen_nbs behaviour
%% -----------------------------------------------------------------

-spec await(Msgs :: msg()) -> term().
await(Msg) ->
    await(Msg, ?DEFAULT_TIMEOUT).

-spec await(Msgs :: msg(), Timeout :: timeout()) -> term().
await(Msg, Timeout) ->
    Self = self(),
    spawn(fun() ->
                  Tag = make_ref(),
                  Refs = gen_nbs_refs:new(),
                  Await = gen_nbs:transmit(Msg, Tag, Timeout),
                  Refs1 = gen_nbs_refs:reg(Await, Refs),
                  Ack = do_receive(Tag, Refs1),
                  Self ! {return, Ack}
          end),
    receive
        {return, Ack} ->
            Ack
    end.

do_receive(Tag, Refs) ->
    {Ref, Result, Msg} = receive
                             {'DOWN', R, process, _Pid, _Info} ->
                                 {R, fail, down};
                             ?RES(R, Res, M) ->
                                 {R, Res, M}
                         end,
    case gen_nbs_refs:use(Result, Msg, Ref, Refs) of
        {ok, Refs1} ->
            do_receive(Tag, Refs1);
        {ack, Ack, Tag, TimerRef, _Refs1} ->
            erlang:cancel_timer(TimerRef),
            Ack
    end.

%% -----------------------------------------------------------------
%% Asynchronous broadcast, returns nothing, it's just send 'n' pray
%%------------------------------------------------------------------
-spec abcast(Name :: dest(), Msg :: term()) -> abcast.
abcast(Name, Msg) when is_atom(Name) ->
    abcast([node() | nodes()], Name, Msg).

-spec abcast(Nodes :: [atom()], Name :: atom(), Msg :: term()) -> abcast.
abcast(Nodes, Name, Msg) when is_list(Nodes), is_atom(Name) ->
    Fun = fun(Node) -> do_send({Name, Node}, ?CAST(Msg)) end,
    ok = lists:foreach(Fun, Nodes),
    abcast.

%% -----------------------------------------------------------------
%% Send functions
%% -----------------------------------------------------------------
%%

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

do_send({global, Name}, Cmd) ->
    catch global:send(Name, Cmd);
do_send({via, Mod, Name}, Cmd) ->
    catch Mod:send(Name, Cmd);
do_send({Name, Node}=Dest, Cmd) when is_atom(Name), is_atom(Node) ->
    do_default_send(Dest, Cmd);
do_send(Dest, Cmd) when is_atom(Dest) ->
    do_default_send(Dest, Cmd);
do_send(Dest, Cmd) when is_pid(Dest) ->
    do_default_send(Dest, Cmd).

do_default_send(Dest, Cmd) ->
    case catch erlang:send(Dest, Cmd, [noconnect]) of
        noconnect ->
            spawn(erlang, send, [Dest, Cmd]);
        Other ->
            Other
    end,
    ok.

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
    InnerState = #inner_state{parent = Parent,
                   name = Name,
                   state = State,
                   mod = Mod,
                   timeout = Timeout,
                   refs = gen_nbs_refs:new(),
                   debug = Debug},
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
    InnerState = #inner_state{parent = Parent,
                   name = Name,
                   mod = Mod,
                   refs = gen_nbs_refs:new(),
                   debug = Debug},
    case catch Mod:init(Args) of
        {ok, State} ->
            proc_lib:init_ack(Starter, {ok, self()}),
            loop(InnerState#inner_state{state = State,
                             timeout = infinity});
        {ok, State, Timeout} ->
            proc_lib:init_ack(Starter, {ok, self()}),
            loop(InnerState#inner_state{state = State,
                             timeout = Timeout});
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

try_dispatch(Info={'DOWN', Ref, process, _Pid, _Info}, Mod, State, Refs) ->
    case maps:is_key(Ref, Refs) of
        true ->
            try_dispatch(?FAIL(Ref, down), Mod, State, Refs);
        false ->
            try_handle(Mod, handle_info, [Info, State], Refs)
    end;

try_dispatch(?CAST(Msg), Mod, State, Refs) ->
    try_handle(Mod, handle_cast, [Msg, State], Refs);
try_dispatch(?MSG(From, Msg), Mod, State, Refs) ->
    try_handle(Mod, handle_msg, [Msg, From, State], Refs);
try_dispatch(?RES(Ref, Result, Reason), Mod, State, Refs) ->
    case gen_nbs_refs:use(Result, Reason, Ref, Refs) of
        {ok, Refs1} ->
            {ok, Refs1};
        {ack, Ack, Tag, TimerRef, Refs1} ->
            erlang:cancel_timer(TimerRef),
            try_handle(Mod, handle_ack, [Ack, Tag, State], Refs1)
    end;

try_dispatch(Info, Mod, State, Refs) ->
    try_handle(Mod, handle_info, [Info, State], Refs).

try_handle(Mod, Func, Args, Refs) ->
    try
        Reply = erlang:apply(Mod, Func, Args),
        {ok, Reply, Refs}
    catch
        throw:R ->
            {ok, R, Refs};
        error:R:Stacktrace ->
            {'EXIT', {R, Stacktrace}, {R, Stacktrace}};
        exit:R:Stacktrace ->
            {'EXIT', R, {R, Stacktrace}}
    end.

try_terminate(Mod, Reason, State, Refs) ->
    try
        {ok, Mod:terminate(Reason, State)}
    catch
        throw:R ->
            {ok, R, Refs};
        error:R:Stacktrace ->
            {'EXIT', {R, Stacktrace}, {R, Stacktrace}};
        exit:R:Stacktrace ->
            {'EXIT', R, {R, Stacktrace}}
    end.

%%% ---------------------------------------------------
%%% Message handling functions
%%% ---------------------------------------------------

handle_msg(Msg, InnerState=#inner_state{mod=Mod,
                             state=State,
                             refs=Refs}) ->
    Reply = try_dispatch(Msg, Mod, State, Refs),
    case Reply of
        {ok, NRefs} ->
            loop(InnerState#inner_state{refs = NRefs});
        {ok, InnerReply, NRefs} ->
            NState = handle_inner_reply(InnerReply, Msg,
                                        InnerState#inner_state{refs = NRefs}),
            loop(NState);
        {'EXIT', ExitReason, ReportReason} ->
            terminate(ExitReason, ReportReason, InnerState)
    end.

handle_inner_reply(Reply, Msg, InnerState=#inner_state{refs=Refs, debug=[]}) ->
    case Reply of
        {await, Await, NState}->
            NRefs = gen_nbs_refs:reg(Await, Refs),
            InnerState#inner_state{state = NState,
                                      refs = NRefs,
                                      timeout = infinity};
        {await, Await, NState, Time} ->
            NRefs = gen_nbs_refs:reg(Await, Refs),
            InnerState#inner_state{state = NState,
                                      refs = NRefs,
                                      timeout = Time};
        {ack, ?FROM(From, Ref), Ack, NState} ->
            From ! ?ACK(Ref, Ack),
            InnerState#inner_state{state = NState,
                        timeout = infinity};
        {ack, ?FROM(From, Ref), Ack, NState, Time} ->
            From ! ?ACK(Ref, Ack),
            InnerState#inner_state{state = NState,
                        timeout = Time};
        {fail, ?FROM(From, Ref), Reason, NState} ->
            From ! ?FAIL(Ref, Reason),
            InnerState#inner_state{state = NState,
                        timeout = infinity};
        {fail, ?FROM(From, Ref), Reason, NState, Time} ->
            From ! ?FAIL(Ref, Reason),
            InnerState#inner_state{state = NState,
                        timeout = Time};
        {ok, NState} ->
            InnerState#inner_state{state = NState,
                        timeout = infinity};
        {ok, NState, Time} ->
            InnerState#inner_state{state = NState,
                        timeout = Time};
        {stop, Reason, NState} ->
            terminate(Reason, Msg, InnerState#inner_state{state = NState});
        BadReply ->
            terminate({bad_return_value, BadReply}, Msg, InnerState)
    end;

handle_inner_reply(Reply, Msg, InnerState=#inner_state{refs=Refs}) ->
    case Reply of
        {await, Await, NState}->
            NRefs = gen_nbs_refs:reg(Await, Refs),
            NInnerState = InnerState#inner_state{state = NState,
                                      refs = NRefs,
                                      timeout = infinity},
            debug(?AWAIT_RET(Await), NInnerState);
        {await, Await, NState, Time} ->
            NRefs = gen_nbs_refs:reg(Await, Refs),
            NInnerState = InnerState#inner_state{state = NState,
                                      refs = NRefs,
                                      timeout = Time},
            debug(?AWAIT_RET(Await), NInnerState);
        {ack, ?FROM(From, Ref)=Tag, Ack, NState} ->
            From ! ?ACK(Ref, Ack),
            NInnerState = InnerState#inner_state{state = NState,
                        timeout = infinity},
            debug(?ACK_RET(Tag), NInnerState);
        {ack, ?FROM(From, Ref)=Tag, Ack, NState, Time} ->
            From ! ?ACK(Ref, Ack),
            NInnerState = InnerState#inner_state{state = NState,
                        timeout = Time},
            debug(?ACK_RET(Tag), NInnerState);
        {fail, ?FROM(From, Ref)=Tag, Reason, NState} ->
            From ! ?FAIL(Ref, Reason),
            NInnerState = InnerState#inner_state{state = NState,
                        timeout = infinity},
            debug(?FAIL_RET(Tag), NInnerState);
        {fail, ?FROM(From, Ref)=Tag, Reason, NState, Time} ->
            From ! ?FAIL(Ref, Reason),
            NInnerState = InnerState#inner_state{state = NState,
                        timeout = Time},
            debug(?FAIL_RET(Tag), NInnerState);
        {ok, NState} ->
            NInnerState = InnerState#inner_state{state = NState,
                        timeout = infinity},
            debug(?OK_RET(NState), NInnerState);
        {ok, NState, Time} ->
            NInnerState = InnerState#inner_state{state = NState,
                        timeout = Time},
            debug(?OK_RET(NState), NInnerState);
        {stop, Reason, NState} ->
            terminate(Reason, Msg, InnerState#inner_state{state = NState});
        BadReply ->
            terminate({bad_return_value, BadReply}, Msg, InnerState)
    end.
%%-----------------------------------------------------------------
%% Callback functions for system messages handling.
%%-----------------------------------------------------------------
system_continue(Parent, Debug, InnerState) ->
    loop(InnerState#inner_state{debug=Debug, parent=Parent}).

-spec system_terminate(_, _, _, [_]) -> no_return().

system_terminate(Reason, _Parent, Debug, InnerState) ->
    terminate(Reason, [], InnerState#inner_state{debug = Debug}).

system_code_change(InnerState=#inner_state{mod=Mod, state=State}, _Module, OldVsn, Extra) ->
    case catch Mod:code_change(OldVsn, State, Extra) of
        {ok, NewState} -> {ok, InnerState#inner_state{state = NewState}};
        Else -> Else
    end.

system_get_state(#inner_state{state=State}) ->
    {ok, State}.

system_replace_state(StateFun, InnerState=#inner_state{state=State}) ->
    NState = StateFun(State),
    {ok, NState, InnerState#inner_state{state = NState}}.

%%% ---------------------------------------------------
%%% Debug functions
%%% ---------------------------------------------------

debug(Msg, InnerState=#inner_state{name=Name,
                        debug=Debug}) ->
    Debug1 = sys:handle_debug(Debug, fun print_event/3, Name,
                              Msg),
    InnerState#inner_state{debug = Debug1}.

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
print_event(Dev, ?FAIL(Ref, Reason), Name) ->
    io:format(Dev, "*DBG* ~p message to ~p has failed with reason ~p~n",
              [Name, Ref, Reason]);
print_event(Dev, ?MSG(Tag, Msg), Name) ->
    io:format(Dev, "*DBG* ~p got msg ~p from ~p~n",
              [Name, Msg, Tag]);
print_event(Dev, ?OK_RET(State), Name) ->
    io:format(Dev, "*DBG* ~p new state ~p~n", [Name, State]);
print_event(Dev, ?ACK_RET(Tag), Name) ->
    io:format(Dev, "*DBG* ~p sent acknowledgement to ~p~n", [Name, Tag]);
print_event(Dev, ?FAIL_RET(Tag), Name) ->
    io:format(Dev, "*DBG* ~p sent fail to ~p~n", [Name, Tag]);
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
                                           debug=Debug,
                                           refs=Refs}) ->
    Reply = try_terminate(Mod, ExitReason, State, Refs),
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
    Log = sys:get_log(Debug),
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
