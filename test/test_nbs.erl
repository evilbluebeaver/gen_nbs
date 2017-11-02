-module(test_nbs).

%%
%% Gen_nbs exports
%%
-export([init/1, handle_cast/2,
         handle_msg/3,
         handle_info/2,
         handle_ack/3,
         code_change/3,
         terminate/2]).

%%
%% Gen_nbs callbacks
%%

init([]) ->
    {ok, []};
init({timeout, Timeout}) ->
    {ok, [], Timeout};
init(ignore) ->
    ignore;
init(stop) ->
    {stop, stopped};
init(hibernate) ->
    {ok,[],hibernate};
init(invalid) ->
    invalid;
init(trap_exit) ->
    process_flag(trap_exit, true),
    {ok, []};
init({notify, Pid}) ->
    {ok, {notify, Pid}}.

terminate(error, _) ->
    error(some_error);
terminate(throw, _) ->
    throw(some_error);
terminate(exit, _) ->
    exit(some_error);
terminate(_, _) ->
    ok.

code_change(_, State, normal) ->
    {ok, State};
code_change(_, _State, error) ->
    error.

handle_cast({transmit_timeout, Msg, Timeout}, State) ->
    Await = gen_nbs:transmit(Msg, make_ref(), 2 * Timeout),
    {await, Await, State, Timeout};

handle_cast({transmit, Msgs}, State) when is_list(Msgs) ->
    Fun = fun(Msg) -> gen_nbs:transmit(Msg, make_ref()) end,
    Awaits = lists:map(Fun, Msgs),
    {await, Awaits, State};

handle_cast({transmit, Msg}, State) ->
    Await = gen_nbs:transmit(Msg, make_ref()),
    {await, Await, State};

handle_cast({transmit, Msg, Timeout}, State) ->
    Await = gen_nbs:transmit(Msg, make_ref(), Timeout),
    {await, Await, State};

handle_cast(exit, _State) ->
    exit(some_error);
handle_cast(error, _State) ->
    error(some_error);
handle_cast(throw, _State) ->
    throw(some_error);
handle_cast({timeout, Timeout}, State) ->
    {ok, State, Timeout};
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(Msg, State={notify, Pid}) ->
    Pid ! {self(), {cast, Msg}},
    {ok, State}.

handle_msg({fail, Reason}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {fail, Reason, From}},
    {fail, F, Reason, State};

handle_msg({fail, Reason, Timeout}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {fail, Reason, From}},
    {fail, F, Reason, State, Timeout};

handle_msg({no_ack, Msg}, {From, _}, State={notify, Pid}) ->
    Pid ! {self(), {no_ack, Msg, From}},
    {ok, State};

handle_msg({ack, Msg}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {ack, Msg, From}},
    {ack, F, Msg, State};

handle_msg({ack, Msg, Timeout}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {ack, Msg, From}},
    {ack, F, Msg, State, Timeout};

handle_msg({long_ack, Msg, Timeout}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {long_ack, Msg, From}},
    timer:sleep(Timeout),
    {ack, F, Msg, State};

handle_msg({manual_fail, Reason}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {manual_fail, Reason, From}},
    gen_nbs:fail(F, Reason),
    {ok, State};

handle_msg({manual_ack, Msg}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {manual_ack, Msg, From}},
    gen_nbs:ack(F, Msg),
    {ok, State}.

handle_ack(Ack, _Tag, State={notify, Pid}) ->
    Pid ! {self(), Ack},
    {ok, State}.

handle_info(Msg, State={notify, Pid}) ->
    Pid ! {self(), {info, Msg}},
    {ok, State}.

