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
         test_info/1,
         test_msg/1,
         test_misc/1,
         test_error/1]).

-define(TIMEOUT, 100).
-define(TEST_MODULE, test_gen_nbs).

%%
%% CT functions
%%
groups() ->
    [{messages, [], [test_cast, test_info, test_msg, test_misc, test_error]},
     {enter_loop, [], [test_enter_loop, test_enter_loop_local, test_enter_loop_global, test_enter_loop_via]}].

all() ->
    [test_start,
     {group, enter_loop},
     {group, messages},
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
    {links, Links} = process_info(self(), links),
    [{trap_flag, TrapFlag}, {links, lists:sort(Links)} | Config].

end_per_testcase(Test, Config) ->
    TrapFlag = proplists:get_value(trap_flag, Config),
    Links = proplists:get_value(links, Config),
    process_flag(trap_exit, TrapFlag),
    {links, NewLinks} = process_info(self(), links),
    case Links == lists:sort(NewLinks) of
        false ->
            {fail, [Test, links]};
        true ->
            receive
                Else -> {fail, [Test, Else]}
            after 0 ->
                      ok
            end
    end.

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
    wait_for_exit(Pid7),

    {ok, Pid8} = gen_nbs:start_link({local, test_name}, ?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid8),
    gen_nbs:stop(Pid8),
    false = erlang:is_process_alive(Pid8),
    undefined = erlang:whereis(test_name),
    wait_for_exit(Pid8),

    {ok, Pid9} = gen_nbs:start(?TEST_MODULE, [], []),
    true = erlang:is_process_alive(Pid9),
    gen_nbs:stop(Pid9, {shutdown, shutdown}, ?TIMEOUT),
    false = erlang:is_process_alive(Pid9),

    Pid10 = erlang:spawn_link(fun() -> gen_nbs:start_link({local, test_name}, ?TEST_MODULE, trap_exit, [])  end),
    wait_for_exit(Pid10),
    undefined = erlang:whereis(test_name),

    ok.

test_enter_loop(_Config) ->
    Pid1 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [])
                               end),
    gen_nbs:stop(Pid1),
    wait_for_exit(Pid1),

    erlang:register(test_name, self()),
    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [])
                               end),
    gen_nbs:stop(Pid2),
    erlang:unregister(test_name),
    wait_for_exit(Pid2),

    erlang:register(test_name, self()),
    Pid3 = proc_lib:spawn_link(fun() ->
                                       erlang:unregister(test_name),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [])
                               end),
    wait_for_exit(Pid3),

    Pid4 = spawn_link(fun() ->
                              gen_nbs:enter_loop(?TEST_MODULE, [], [])
                      end),
    wait_for_exit(Pid4),

    Pid5 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], ?TIMEOUT)
                               end),
    gen_nbs:stop(Pid5),
    wait_for_exit(Pid5),
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
    wait_for_exit(Pid1),

    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {local, test_name})
                               end),
    wait_for_exit(Pid2),
    undefined = whereis(test_name),

    Pid3 = proc_lib:spawn_link(fun() ->
                                       erlang:register(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {local, test_name_2})
                               end),
    wait_for_exit(Pid3),
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
    wait_for_exit(Pid1),
    undefined = global:whereis_name(test_name),

    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name})
                               end),
    wait_for_exit(Pid2),
    undefined = global:whereis_name(test_name),

    Pid3 = proc_lib:spawn_link(fun() ->
                                       global:register_name(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name_2})
                               end),
    wait_for_exit(Pid3),
    undefined = global:whereis_name(test_name),

    global:register_name(test_name, self()),
    Pid4 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {global, test_name})
                               end),
    wait_for_exit(Pid4),
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
    wait_for_exit(Pid1),
    undefined = global:whereis_name(test_name),

    Pid2 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name})
                               end),
    wait_for_exit(Pid2),
    undefined = global:whereis_name(test_name),

    Pid3 = proc_lib:spawn_link(fun() ->
                                       global:register_name(test_name, self()),
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name_2})
                               end),
    wait_for_exit(Pid3),
    undefined = global:whereis_name(test_name),

    global:register_name(test_name, self()),
    Pid4 = proc_lib:spawn_link(fun() ->
                                       gen_nbs:enter_loop(?TEST_MODULE, [], [], {via, global, test_name})
                               end),
    wait_for_exit(Pid4),
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
    wait_for_exit(Pid),
    ok.

test_cast(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, []),
    gen_nbs:cast(Pid, message),
    wait_for_msg(Pid, {cast, message}),
    gen_nbs:stop(Pid),
    wait_for_exit(Pid),
    ok.

test_error(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid1, error),
    wait_for_exit(Pid1),

    {ok, Pid2} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid2, throw),
    wait_for_exit(Pid2),

    {ok, Pid3} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid3, exit),
    wait_for_exit(Pid3),

    {ok, Pid4} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    catch gen_nbs:stop(Pid4, error, ?TIMEOUT),
    wait_for_exit(Pid4),

    {ok, Pid5} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:stop(Pid5, throw, ?TIMEOUT),
    wait_for_exit(Pid5),

    {ok, Pid6} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    catch gen_nbs:stop(Pid6, exit, ?TIMEOUT),
    wait_for_exit(Pid6),

    {ok, Pid7} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, trace}]),
    gen_nbs:stop(Pid7, unknown, ?TIMEOUT),
    wait_for_exit(Pid7),

    ok.

test_misc(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    gen_nbs:cast(Pid1, {timeout, ?TIMEOUT}),
    timer:sleep(?TIMEOUT),
    wait_for_msg(Pid1, {info, timeout}),
    gen_nbs:cast(Pid1, stop),
    wait_for_exit(Pid1),
    ok.

test_info(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    Msg = message,
    Pid ! Msg,
    wait_for_msg(Pid, {info, Msg}),
    gen_nbs:stop(Pid),
    wait_for_exit(Pid),
    ok.

test_msg(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, Pid2} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    Msg = message,
    %%
    %% No ack
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, Pid2, ?TIMEOUT}),
    wait_for_msg(Pid2, {msg, Msg, Pid1}),
    timer:sleep(?TIMEOUT),
    wait_for_msg(Pid1, {fail, Pid2}),

    %%
    %% Post with no ack needed
    %%
    gen_nbs:cast(Pid1, {msg_no_ack, Msg, Pid2, infinity}),
    wait_for_msg(Pid2, {msg, Msg, Pid1}),

    %%
    %% Successful ack
    %%
    gen_nbs:cast(Pid1, {msg_ack, Msg, Pid2}),
    wait_for_msg(Pid2, {msg, Msg, Pid1}),
    timer:sleep(?TIMEOUT),
    wait_for_msg(Pid1, {ack, Pid2}),

    %%
    %% Long ack
    %%
    gen_nbs:cast(Pid1, {msg_long_ack, Msg, Pid2, ?TIMEOUT}),
    wait_for_msg(Pid2, {msg, Msg, Pid1}),
    timer:sleep(?TIMEOUT),
    wait_for_msg(Pid1, {fail, Pid2}),
    %%
    %% Ack with timeout after it
    %%
    gen_nbs:cast(Pid1, {msg_ack_timeout, Msg, Pid2, ?TIMEOUT}),
    wait_for_msg(Pid2, {msg, Msg, Pid1}),
    wait_for_msg(Pid1, {ack, Pid2}),
    timer:sleep(?TIMEOUT),
    wait_for_msg(Pid2, {info, timeout}),

    %%%
    %%% Notify after timeout
    %%%
    gen_nbs:cast(Pid1, {msg_suspend, Msg, Pid2, ?TIMEOUT}),
    wait_for_msg(Pid2, {msg, Msg, Pid1}),
    wait_for_msg(Pid1, {fail, Pid2}),

    gen_nbs:stop(Pid1),
    gen_nbs:stop(Pid2),
    wait_for_exit(Pid1),
    wait_for_exit(Pid2),
    ok.

wait_for_msg(Pid, Msg) ->
    receive
        {Pid, Msg} ->
            ok;
        Else ->
            ct:fail(Else)
    after 5000 ->
              ct:fail(timeout)
    end.

wait_for_exit(Pid) ->
    receive
        {'EXIT', Pid, _} ->
            ok
    after 5000 ->
              ct:fail(timeout)
    end.

