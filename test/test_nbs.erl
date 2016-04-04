-module(test_nbs).

%%
%% Gen_nbs exports
%%
-export([init/1, handle_cast/2,
         handle_msg/3,
         handle_info/2,
         handle_ack/3,
         handle_fail/2,
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
handle_cast({msg_multiple, Msg, To, Timeout}, State) ->
    Await1 = gen_nbs:msg(To, {ack, Msg}, tag, Timeout),
    Await2 = gen_nbs:msg(To, {ack, Msg}, tag, Timeout),
    {await, [Await1, Await2], State};
handle_cast({msg_no_ack, Msg, To, Timeout}, State) ->
    Await = gen_nbs:msg(To, Msg, tag, Timeout),
    {await, Await, State};
handle_cast({msg_no_await, Msg, To, Timeout}, State) ->
    _Await = gen_nbs:msg(To, Msg, tag, Timeout),
    {ok, State};
handle_cast({msg_await_timeout, Timeout}, State) ->
    {await, [], State, Timeout};
handle_cast({msg_manual_ack, Msg, To}, State) ->
    Await = gen_nbs:msg(To, {manual_ack, Msg}, tag),
    {await, Await, State};
handle_cast({msg_manual_fail, Msg, To}, State) ->
    Await = gen_nbs:msg(To, {manual_fail, Msg}, tag),
    {await, Await, State};
handle_cast({msg_ack, Msg, To}, State) ->
    Await = gen_nbs:msg(To, {ack, Msg}, tag),
    {await, Await, State};
handle_cast({msg_long_ack, Msg, To, Timeout}, State) ->
    Await = gen_nbs:msg(To, {long_ack, Timeout, Msg}, tag, Timeout),
    {await, Await, State};
handle_cast({msg_ack_timeout, Msg, To, Timeout}, State) ->
    Await = gen_nbs:msg(To, {timeout, Timeout, Msg}, tag, Timeout),
    {await, Await, State};
handle_cast({fail, To}, State) ->
    Await = gen_nbs:msg(To, {fail}, tag),
    {await, Await, State};
handle_cast({fail, To, Timeout}, State) ->
    Await = gen_nbs:msg(To, {fail, Timeout}, tag),
    {await, Await, State};
handle_cast(Msg, State={notify, Pid}) ->
    Pid ! {self(), {cast, Msg}},
    {ok, State}.

handle_msg({fail}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {fail, From}},
    {fail, F, State};
handle_msg({fail, Timeout}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {fail, From}},
    {fail, F, State, Timeout};
handle_msg({long_ack, Timeout, Msg}, F={From, _}, State={notify, Pid}) ->
    timer:sleep(Timeout),
    Pid ! {self(), {msg, Msg, From}},
    {ack, F, ok, State};
handle_msg({timeout, Timeout, Msg}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {msg, Msg, From}},
    {ack, F, ok, State, Timeout};
handle_msg({manual_ack, Msg}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {msg, Msg, From}},
    gen_nbs:ack(F, ok),
    {ok, State};
handle_msg({manual_fail, Msg}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {msg, Msg, From}},
    gen_nbs:fail(F),
    {ok, State};
handle_msg({ack, Msg}, F={From, _}, State={notify, Pid}) ->
    Pid ! {self(), {msg, Msg, From}},
    {ack, F, ok, State};
handle_msg(Msg, {From, _}, State={notify, Pid}) ->
    Pid ! {self(), {msg, Msg, From}},
    {ok, State}.

handle_ack(ok, tag, State={notify, Pid}) ->
    Pid ! {self(), ack},
    {ok, State}.

handle_fail(tag, State={notify, Pid}) ->
    Pid ! {self(), fail},
    {ok, State}.

handle_info(Msg, State={notify, Pid}) ->
    Pid ! {self(), {info, Msg}},
    {ok, State}.

