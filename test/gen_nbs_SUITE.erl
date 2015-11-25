-module(gen_nbs_SUITE).

%%
%% CT exports
%%
-export([groups/0,
         all/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2]).

%%
%% Test exports
%%
-export([test_start/1,
         test_enter_loop/1,
         test_enter_loop_local/1,
         test_enter_loop_global/1,
         test_enter_loop_via/1,
         test_sys/1,
         test_cast/1,
         test_abcast/1,
         test_multimsg/1,
         test_info/1,
         test_msg/1,
         test_send/1,
         test_ref/1,
         test_misc/1,
         test_format_status/1,
         test_error/1]).

-define(TIMEOUT, 100).
-define(TEST_MODULE, test_nbs).
-define(TEST_FORMAT_MODULE, test_nbs_format).

-define(CHECK_AFTER,
    receive
        Else -> {fail, [Test, Else]}
    after ?TIMEOUT ->
              ok
    end).
-define(WAIT_FOR_MSG(MSG),
        receive
            MSG ->
                ok
        after 5000 ->
                  ct:fail(timeout)
        end).

-define(WAIT_FOR_DOWN(PID),
        ?WAIT_FOR_MSG({'DOWN', _, process, PID, _})).

-define(WAIT_FOR_EXIT(PID),
        ?WAIT_FOR_MSG({'EXIT', PID, _})).

%%
%% CT functions
%%
groups() ->
    [{messages, [], [test_cast, test_info, test_msg, test_misc, test_error, test_send, test_ref, test_abcast, test_multimsg]},
     {enter_loop, [], [test_enter_loop, test_enter_loop_local, test_enter_loop_global, test_enter_loop_via]}].

all() ->
    [test_start,
     {group, enter_loop},
     {group, messages},
     test_format_status,
     test_sys].

init_per_suite(Config) ->
    error_logger:tty(false),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_, Config) ->
    Config.

end_per_group(_, _Config) ->
    ok.

init_per_testcase(_, Config) ->
    TrapFlag = process_flag(trap_exit, true),
    [{trap_flag, TrapFlag} | Config].

end_per_testcase(Test, Config) ->
    TrapFlag = proplists:get_value(trap_flag, Config),
    process_flag(trap_exit, TrapFlag),
    ?CHECK_AFTER.

%%
%% Test functions
%%
test_start(_Config) ->
    {ok, Pid0} = gen_nbs:start(?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid0),
    gen_nbs:stop(Pid0),
    false = erlang:is_process_alive(Pid0),

    {ok, Pid1} = gen_nbs:start(?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid1),
    gen_nbs:stop(Pid1, shutdown, ?TIMEOUT),
    false = erlang:is_process_alive(Pid1),

    {ok, Pid2} = gen_nbs:start(?TEST_MODULE, {timeout, ?TIMEOUT}, []),
    true = erlang:is_process_alive(Pid2),
    gen_nbs:stop(Pid2),
    false = erlang:is_process_alive(Pid2),

    ignore = gen_nbs:start(?TEST_MODULE, ignore, []),
    ignore = gen_nbs:start({local, test_name}, ?TEST_MODULE, ignore, []),
    ignore = gen_nbs:start({global, test_name}, ?TEST_MODULE, ignore, []),
    ignore = gen_nbs:start({via, global, test_name}, ?TEST_MODULE, ignore, []),

    {error, stopped} = gen_nbs:start(?TEST_MODULE, stop, []),

    {ok, Pid3} = gen_nbs:start(?TEST_MODULE, hibernate, []),
    true = erlang:is_process_alive(Pid3),
    gen_nbs:stop(Pid3),
    false = erlang:is_process_alive(Pid3),

    {error, _} = gen_nbs:start(?TEST_MODULE, unknown, []),

    {error, _} = gen_nbs:start(?TEST_MODULE, invalid, []),

    {ok, Pid4} = gen_nbs:start({local, test_name}, ?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid4),
    gen_nbs:stop(test_name),
    false = erlang:is_process_alive(Pid4),
    undefined = erlang:whereis(test_name),

    {ok, Pid5} = gen_nbs:start({global, test_name}, ?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid5),
    gen_nbs:stop({global, test_name}),
    false = erlang:is_process_alive(Pid5),
    undefined = global:whereis_name(test_name),

    {ok, Pid6} = gen_nbs:start({via, global, test_name}, ?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid6),
    gen_nbs:stop({via, global, test_name}),
    false = erlang:is_process_alive(Pid6),
    undefined = global:whereis_name(test_name),


    {ok, Pid7} = gen_nbs:start_link(?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid7),
    gen_nbs:stop(Pid7),
    false = erlang:is_process_alive(Pid7),
    ?WAIT_FOR_EXIT(Pid7),

    {ok, Pid8} = gen_nbs:start_link({local, test_name}, ?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid8),
    gen_nbs:stop(Pid8),
    false = erlang:is_process_alive(Pid8),
    undefined = erlang:whereis(test_name),
    ?WAIT_FOR_EXIT(Pid8),

    {ok, Pid9} = gen_nbs:start(?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid9),
    gen_nbs:stop(Pid9, {shutdown, shutdown}, ?TIMEOUT),
    false = erlang:is_process_alive(Pid9),

    Pid10 = erlang:spawn_link(fun() -> gen_nbs:start_link({local, test_name}, ?TEST_MODULE, trap_exit, [])  end),
    ?WAIT_FOR_EXIT(Pid10),
    undefined = erlang:whereis(test_name),

    ok.

test_enter_loop(_Config) ->
    Pid1 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [])
                               end),
    gen_nbs:stop(Pid1),
    ?WAIT_FOR_EXIT(Pid1),

    erlang:register(test_name, self()),
    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [])
                               end),
    gen_nbs:stop(Pid2),
    erlang:unregister(test_name),
    ?WAIT_FOR_EXIT(Pid2),

    erlang:register(test_name, self()),
    Pid3 = proc_lib:spawn_link(fun() ->
                                       erlang:unregister(test_name),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [])
                               end),
    ?WAIT_FOR_EXIT(Pid3),

    Pid4 = spawn_link(fun() ->
                              gen_nbs:enter_loop(?TEST_MODULE, [], [])
                      end),
    ?WAIT_FOR_EXIT(Pid4),

    Pid5 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], ?TIMEOUT)
                               end),
    gen_nbs:stop(Pid5),
    ?WAIT_FOR_EXIT(Pid5),
    ok.

%%
%% Local registration
%%
test_enter_loop_local(_Config) ->
    Pid1 = proc_lib:spawn_link(fun() ->
                                       erlang:register(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {local, test_name})
                               end),
    gen_nbs:stop(Pid1),
    undefined = whereis(test_name),
    ?WAIT_FOR_EXIT(Pid1),

    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {local, test_name})
                               end),
    ?WAIT_FOR_EXIT(Pid2),
    undefined = whereis(test_name),

    Pid3 = proc_lib:spawn_link(fun() ->
                                       erlang:register(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {local, test_name_2})
                               end),
    ?WAIT_FOR_EXIT(Pid3),
    undefined = whereis(test_name),

    ok.

%%
%% Global registration
%%
test_enter_loop_global(_Config) ->
    Pid1 = proc_lib:spawn_link(fun() ->
                                       global:register_name(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name})
                               end),
    gen_nbs:stop(Pid1),
    ?WAIT_FOR_EXIT(Pid1),
    undefined = global:whereis_name(test_name),

    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name})
                               end),
    ?WAIT_FOR_EXIT(Pid2),
    undefined = global:whereis_name(test_name),

    Pid3 = proc_lib:spawn_link(fun() ->
                                       global:register_name(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name_2})
                               end),
    ?WAIT_FOR_EXIT(Pid3),
    undefined = global:whereis_name(test_name),

    global:register_name(test_name, self()),
    Pid4 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name})
                               end),
    ?WAIT_FOR_EXIT(Pid4),
    global:unregister_name(test_name),

    ok.

%%
%% Via module registration
%%
test_enter_loop_via(_Config) ->
    Pid1 = proc_lib:spawn_link(fun() ->
                                       global:register_name(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name})
                               end),
    gen_nbs:stop(Pid1),
    ?WAIT_FOR_EXIT(Pid1),
    undefined = global:whereis_name(test_name),

    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name})
                               end),
    ?WAIT_FOR_EXIT(Pid2),
    undefined = global:whereis_name(test_name),

    Pid3 = proc_lib:spawn_link(fun() ->
                                       global:register_name(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name_2})
                               end),
    ?WAIT_FOR_EXIT(Pid3),
    undefined = global:whereis_name(test_name),

    global:register_name(test_name, self()),
    Pid4 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name})
                               end),
    ?WAIT_FOR_EXIT(Pid4),
    global:unregister_name(test_name),

    ok.

test_sys(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, [], []),
    sys:suspend(Pid),
    sys:change_code(Pid, ?TEST_MODULE, "0", normal),
    sys:resume(Pid),

    sys:suspend(Pid),
    sys:change_code(Pid, ?TEST_MODULE, "0", error),
    sys:resume(Pid),

    [] = sys:get_state(Pid),
    [] = sys:replace_state(Pid, fun(S) -> S end),
    _ = sys:get_status(Pid),
    gen_nbs:stop(Pid),
    ?WAIT_FOR_EXIT(Pid),
    ok.

test_cast(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, []),
    gen_nbs:cast(Pid, message),
    ?WAIT_FOR_MSG({Pid, {cast, message}}),
    gen_nbs:stop(Pid),
    ?WAIT_FOR_EXIT(Pid),
    ok.

test_abcast(_Config) ->
    {ok, Pid} = gen_nbs:start_link({local, test_name}, ?TEST_MODULE, {notify, self()}, []),
    gen_nbs:abcast(test_name, message),
    ?WAIT_FOR_MSG({Pid, {cast, message}}),
    gen_nbs:abcast([node()], test_name, message),
    ?WAIT_FOR_MSG({Pid, {cast, message}}),
    gen_nbs:stop(Pid),
    ?WAIT_FOR_EXIT(Pid),
    ok.

test_multimsg(_Config) ->
    {ok, Pid} = gen_nbs:start_link({local, test_name}, ?TEST_MODULE, {notify, self()}, []),
    gen_nbs:multimsg(test_name, message),
    Self = self(),
    ?WAIT_FOR_MSG({Pid, {msg, message, Self}}),
    gen_nbs:multimsg([node()], test_name, message),
    ?WAIT_FOR_MSG({Pid, {msg, message, Self}}),
    gen_nbs:multimsg(test_name, message, infinity),
    ?WAIT_FOR_MSG({Pid, {msg, message, Self}}),
    gen_nbs:multimsg([node()], test_name, message, infinity),
    ?WAIT_FOR_MSG({Pid, {msg, message, Self}}),
    gen_nbs:stop(Pid),
    Node = node(),
    ?WAIT_FOR_DOWN({test_name, Node}),
    ?WAIT_FOR_DOWN({test_name, Node}),
    ?WAIT_FOR_DOWN({test_name, Node}),
    ?WAIT_FOR_DOWN({test_name, Node}),
    ?WAIT_FOR_EXIT(Pid),
    ok.

test_error(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid1, error),
    ?WAIT_FOR_EXIT(Pid1),

    {ok, Pid2} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid2, throw),
    ?WAIT_FOR_EXIT(Pid2),

    {ok, Pid3} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid3, exit),
    ?WAIT_FOR_EXIT(Pid3),

    {ok, Pid4} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    catch gen_nbs:stop(Pid4, error, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid4),

    {ok, Pid5} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:stop(Pid5, throw, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid5),

    {ok, Pid6} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    catch gen_nbs:stop(Pid6, exit, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid6),

    {ok, Pid7} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, trace}]),
    gen_nbs:stop(Pid7, unknown, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid7),

    ok.

test_misc(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    gen_nbs:cast(Pid1, {timeout, ?TIMEOUT}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, {info, timeout}}),
    gen_nbs:cast(Pid1, stop),
    ?WAIT_FOR_EXIT(Pid1),
    ok.

test_info(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    Msg = message,
    Pid ! Msg,
    ?WAIT_FOR_MSG({Pid, {info, Msg}}),
    gen_nbs:stop(Pid),
    ?WAIT_FOR_EXIT(Pid),
    ok.

test_send(_Config) ->
    {ok, Pid1} = gen_nbs:start_link({global, test_name}, ?TEST_MODULE, {notify, self()}, []),
    gen_nbs:cast({global, test_name}, message),
    ?WAIT_FOR_MSG({Pid1, {cast, message}}),
    gen_nbs:stop(Pid1),
    ?WAIT_FOR_EXIT(Pid1),
    undefined = global:whereis_name(test_name),

    {ok, Pid2} = gen_nbs:start_link({via, global, test_name}, ?TEST_MODULE, {notify, self()}, []),
    gen_nbs:cast({via, global, test_name}, message),
    ?WAIT_FOR_MSG({Pid2, {cast, message}}),
    gen_nbs:stop(Pid2),
    ?WAIT_FOR_EXIT(Pid2),
    undefined = global:whereis_name(test_name),

    {ok, Pid3} = gen_nbs:start_link({local, test_name}, ?TEST_MODULE, {notify, self()}, []),
    gen_nbs:cast(test_name, message),
    ?WAIT_FOR_MSG({Pid3, {cast, message}}),
    gen_nbs:stop(Pid3),
    ?WAIT_FOR_EXIT(Pid3),
    undefined = erlang:whereis(test_name),

    %% Fake node send
    gen_nbs:cast({test_name, fake_node}, message).

test_ref(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    Ref1 = gen_nbs:ref(gen_nbs:msg(Pid, message, ?TIMEOUT)),
    Self = self(),

    ?WAIT_FOR_MSG({Pid, {msg, message, Self}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({'$gen_fail', Ref1}),

    _Ref2 = gen_nbs:ref(gen_nbs:msg(Pid, message, infinity)),
    Self = self(),
    ?WAIT_FOR_MSG({Pid, {msg, message, Self}}),

    gen_nbs:stop(Pid),
    ?WAIT_FOR_DOWN(Pid),
    ?WAIT_FOR_DOWN(Pid),
    ?WAIT_FOR_EXIT(Pid).



test_msg(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, Pid2} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, Pid3} = gen_nbs:start_link({local, test_local_name}, ?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, Pid4} = gen_nbs:start_link({global, test_global_name}, ?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    Msg = message,

    %%
    %% No ack
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, Pid2, ?TIMEOUT}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, fail}),

    %
    %% Post with no ack needed
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, Pid2, infinity}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),

    %
    %% Post ack infinity
    %%
    gen_nbs:cast(Pid1, {msg_ack_timeout, Msg, Pid2, infinity}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, ack}),

    %%
    %% Successful ack
    %%
    gen_nbs:cast(Pid1, {msg_ack, Msg, Pid2}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, ack}),

    %%
    %% Long ack
    %%
    gen_nbs:cast(Pid1, {msg_long_ack, Msg, Pid2, ?TIMEOUT}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, fail}),

    %%
    %% Ack with timeout after it
    %%
    gen_nbs:cast(Pid1, {msg_ack_timeout, Msg, Pid2, ?TIMEOUT}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    ?WAIT_FOR_MSG({Pid1, ack}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid2, {info, timeout}}),

    %%
    %% Msg no await
    %%
    gen_nbs:cast(Pid1, {msg_no_await, Msg, Pid2, ?TIMEOUT}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, fail}),

    %%
    %% Msg await timeout
    %%
    gen_nbs:cast(Pid1, {msg_await_timeout, ?TIMEOUT}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, {info, timeout}}),

    %%
    %% Manual ack
    %%
    gen_nbs:cast(Pid1, {msg_manual_ack, Msg, Pid2}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(2 * ?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, ack}),

    %%
    %% Manual fail
    %%
    gen_nbs:cast(Pid1, {msg_manual_fail, Msg, Pid2}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, fail}),

    %%
    %% Multiple msgs
    %%
    gen_nbs:cast(Pid1, {msg_multiple, Msg, Pid2, ?TIMEOUT}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    ?WAIT_FOR_MSG({Pid2, {msg, Msg, Pid1}}),
    ?WAIT_FOR_MSG({Pid1, ack}),
    ?WAIT_FOR_MSG({Pid1, ack}),

    %%
    %% Post with no ack needed (unexisting_process)
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, fake_name, infinity}),
    ?WAIT_FOR_MSG({Pid1, fail}),

    %%
    %% Post (globally registered process)
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, {global, test_global_name}, infinity}),
    ?WAIT_FOR_MSG({Pid4, {msg, Msg, Pid1}}),

    %%
    %% Post ("via mod" registered process)
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, {via, global, test_global_name}, infinity}),
    ?WAIT_FOR_MSG({Pid4, {msg, Msg, Pid1}}),

    %%
    %% Post (fully qualified name)
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, {test_local_name, node()}, infinity}),
    ?WAIT_FOR_MSG({Pid3, {msg, Msg, Pid1}}),

    gen_nbs:stop(Pid1),
    gen_nbs:stop(Pid2),
    gen_nbs:stop(Pid3),
    gen_nbs:stop(Pid4),
    ?WAIT_FOR_EXIT(Pid1),
    ?WAIT_FOR_EXIT(Pid2),
    ?WAIT_FOR_EXIT(Pid3),
    ?WAIT_FOR_EXIT(Pid4),
    ok.

test_format_status(_Config) ->
    ListFun = fun() ->
                      [some_state_info]
              end,
    SimpleFun = fun() ->
                        some_state_info
                end,
    ErrorFun =  fun() ->
                        error(some_error)
                end,
    {ok, Pid1} = gen_nbs:start_link(?TEST_FORMAT_MODULE, {format_status, ListFun}, []),
    {ok, Pid2} = gen_nbs:start_link(?TEST_FORMAT_MODULE, {format_status, SimpleFun}, []),
    {ok, Pid3} = gen_nbs:start_link(?TEST_FORMAT_MODULE, {format_status, ErrorFun}, []),
    {ok, Pid4} = gen_nbs:start_link(?TEST_MODULE, [], []),

    _ = sys:get_status(Pid1),
    _ = sys:get_status(Pid2),
    _ = sys:get_status(Pid3),
    _ = sys:get_status(Pid4),

    gen_nbs:stop(Pid1),
    gen_nbs:stop(Pid2),
    gen_nbs:stop(Pid3),
    gen_nbs:stop(Pid4),
    ?WAIT_FOR_EXIT(Pid1),
    ?WAIT_FOR_EXIT(Pid2),
    ?WAIT_FOR_EXIT(Pid3),
    ?WAIT_FOR_EXIT(Pid4).

