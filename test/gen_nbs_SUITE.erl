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
         test_info/1,
         test_msg/1,
         test_package/1,
         test_send/1,
         test_transmit/1,
         test_await/1,
         test_misc/1,
         test_format_status/1,
         test_error/1]).

-define(TIMEOUT, 100).
-define(TEST_MODULE, test_nbs).
-define(TEST_FORMAT_MODULE, test_nbs_format).

-define(WAIT_FOR_MSG(MSG),
        receive
            MSG ->
                ok
        after 5000 ->
                  ct:fail(timeout)
        end).

-define(WAIT_FOR_EXIT(PID),
        ?WAIT_FOR_MSG({'EXIT', PID, _})).

-include("gen_nbs_await.hrl").

%%
%% CT functions
%%
groups() ->
    [{transmit, [], [test_transmit, test_await]},
     {messages, [], [test_msg, test_package]},
     {stuff, [], [test_format_status, test_start, test_sys]},
     {send, [], [test_cast, test_info, test_misc, test_error, test_send, test_abcast]},
     {enter_loop, [], [test_enter_loop, test_enter_loop_local, test_enter_loop_global, test_enter_loop_via]}].

all() ->
    [{group, stuff},
     {group, messages},
     {group, enter_loop},
     {group, send},
     {group, transmit}].

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
    receive
        Else ->
            {fail, [Test, Else]}
    after ?TIMEOUT ->
              ok
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

test_error(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid1, error),
    ?WAIT_FOR_EXIT(Pid1),

    {ok, Pid2} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid2, throw),
    ?WAIT_FOR_EXIT(Pid2),

    {ok, Pid3} = gen_nbs:start_link(?TEST_MODULE, [], []),
    gen_nbs:cast(Pid3, throw),
    ?WAIT_FOR_EXIT(Pid3),

    {ok, Pid4} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    gen_nbs:cast(Pid4, exit),
    ?WAIT_FOR_EXIT(Pid4),

    {ok, Pid5} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    catch gen_nbs:stop(Pid5, error, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid5),

    {ok, Pid6} = gen_nbs:start_link(?TEST_MODULE, [], []),
    gen_nbs:stop(Pid6, throw, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid6),

    {ok, Pid7} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, [trace]}]),
    catch gen_nbs:stop(Pid7, exit, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid7),

    {ok, Pid8} = gen_nbs:start_link(?TEST_MODULE, [], [{debug, trace}]),
    gen_nbs:stop(Pid8, unknown, ?TIMEOUT),
    ?WAIT_FOR_EXIT(Pid8),

    ok.

test_misc(_Config) ->
    {ok, Pid1} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, Pid2} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, []),
    gen_nbs:cast(Pid1, {timeout, ?TIMEOUT}),
    gen_nbs:cast(Pid2, {timeout, ?TIMEOUT}),
    timer:sleep(?TIMEOUT),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, {info, timeout}}),
    ?WAIT_FOR_MSG({Pid2, {info, timeout}}),
    gen_nbs:cast(Pid1, stop),
    gen_nbs:cast(Pid2, stop),
    ?WAIT_FOR_EXIT(Pid1),
    ?WAIT_FOR_EXIT(Pid2),
    ok.

test_info(_Config) ->
    {ok, Pid} = gen_nbs:start_link(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    Msg = message,
    Pid ! Msg,
    ?WAIT_FOR_MSG({Pid, {info, Msg}}),
    DownMsg = {'DOWN', make_ref(), process, self(), some_info},
    Pid ! DownMsg,
    ?WAIT_FOR_MSG({Pid, {info, DownMsg}}),
    gen_nbs:stop(Pid),
    ?WAIT_FOR_EXIT(Pid),
    ok.

test_msg(_Config) ->
    CompletionFun = fun(D) -> D end,
    Expected1= #msg{dest=test_dest,
                    payload=test_payload,
                    completion_fun=CompletionFun},
    Expected1 = gen_nbs:msg(test_dest, test_payload, CompletionFun),
    Expected2= #msg{dest=test_dest,
                    payload=test_payload},
    Expected2 = gen_nbs:msg(test_dest, test_payload),
    Expected2 = gen_nbs:msg(test_dest, test_payload, undefined),
    ok.

test_package(_Config) ->
    CompletionFun = fun(D) -> D end,
    Msg = #msg{dest=test_dest,
               payload=test_payload},
    Msgs = #{test_tag => Msg},
    Expected1 = #package{children=Msgs,
                         completion_fun=CompletionFun},
    Expected1 = gen_nbs:package(Msgs, CompletionFun),
    Expected2 = #package{children=Msgs},
    Expected2 = gen_nbs:package(Msgs),
    Expected2 = gen_nbs:package(Msgs, undefined),
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

test_transmit(_Config) ->
    {ok, Sender} = gen_nbs:start(?TEST_MODULE, {notify, self()}, []),
    {ok, DebugSender} = gen_nbs:start(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, Pid2} = gen_nbs:start(?TEST_MODULE, {notify, self()}, []),
    {ok, DebugPid2} = gen_nbs:start(?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, DebugPid3} = gen_nbs:start({local, test_local_name}, ?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),
    {ok, DebugPid4} = gen_nbs:start({global, test_global_name}, ?TEST_MODULE, {notify, self()}, [{debug, [trace]}]),

    CompletionFun = fun(D) -> {ok, D} end,

    %%
    %% Fail
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(Pid2, {fail, reason})}),
    gen_nbs:cast(DebugSender, {transmit, gen_nbs:msg(DebugPid2, {fail, reason})}),
    ?WAIT_FOR_MSG({Pid2, {fail, reason, Sender}}),
    ?WAIT_FOR_MSG({DebugPid2, {fail, reason, DebugSender}}),
    ?WAIT_FOR_MSG({Sender, {fail, reason}}),
    ?WAIT_FOR_MSG({DebugSender, {fail, reason}}),

    %%
    %% Fail (timeout)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {fail, reason, ?TIMEOUT})}),
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(Pid2, {fail, reason, ?TIMEOUT})}),
    ?WAIT_FOR_MSG({DebugPid2, {fail, reason, Sender}}),
    ?WAIT_FOR_MSG({Pid2, {fail, reason, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({DebugPid2, {info, timeout}}),
    ?WAIT_FOR_MSG({Pid2, {info, timeout}}),
    ?WAIT_FOR_MSG({Sender, {fail, reason}}),
    ?WAIT_FOR_MSG({Sender, {fail, reason}}),

    %%
    %% No ack
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {no_ack, msg}), ?TIMEOUT}),
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(Pid2, {no_ack, msg}), ?TIMEOUT}),
    ?WAIT_FOR_MSG({DebugPid2, {no_ack, msg, Sender}}),
    ?WAIT_FOR_MSG({Pid2, {no_ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {fail, timeout}}),
    ?WAIT_FOR_MSG({Sender, {fail, timeout}}),


    %%
    %% Ack
    %%
    gen_nbs:cast(DebugSender, {transmit, gen_nbs:msg(DebugPid2, {ack, msg})}),
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(Pid2, {ack, msg})}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg, DebugSender}}),
    ?WAIT_FOR_MSG({Pid2, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({DebugSender, {ack, msg}}),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),

    %%
    %% Ack (timeout)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {ack, msg, ?TIMEOUT})}),
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(Pid2, {ack, msg, ?TIMEOUT})}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg, Sender}}),
    ?WAIT_FOR_MSG({Pid2, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({DebugPid2, {info, timeout}}),
    ?WAIT_FOR_MSG({Pid2, {info, timeout}}),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),

    %%
    %% Ack (after timeout)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {long_ack, msg, 2 * ?TIMEOUT}), ?TIMEOUT}),
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(Pid2, {long_ack, msg, 2 * ?TIMEOUT}), ?TIMEOUT}),
    ?WAIT_FOR_MSG({DebugPid2, {long_ack, msg, Sender}}),
    ?WAIT_FOR_MSG({Pid2, {long_ack, msg, Sender}}),
    timer:sleep(3 * ?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {fail, timeout}}),
    ?WAIT_FOR_MSG({Sender, {fail, timeout}}),

    %%
    %% Await (timeout)
    %%
    gen_nbs:cast(DebugSender, {transmit_timeout, gen_nbs:msg(DebugPid2, {fail, reason}), ?TIMEOUT}),
    gen_nbs:cast(Sender, {transmit_timeout, gen_nbs:msg(Pid2, {fail, reason}), ?TIMEOUT}),
    ?WAIT_FOR_MSG({DebugPid2, {fail, reason, DebugSender}}),
    ?WAIT_FOR_MSG({Pid2, {fail, reason, Sender}}),
    ?WAIT_FOR_MSG({DebugSender, {fail, reason}}),
    ?WAIT_FOR_MSG({Sender, {fail, reason}}),

    %%
    %% Ack (package)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:package(#{tag => gen_nbs:msg(DebugPid2, {ack, msg})})}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, #{tag := {ack, msg}}}),

    %%
    %% Ack (package 2)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:package(#{tag1 => gen_nbs:msg(DebugPid2, {ack, msg1}),
                                                    tag2 => gen_nbs:msg(DebugPid2, {fail, reason})})}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg1, Sender}}),
    ?WAIT_FOR_MSG({DebugPid2, {fail, reason, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, #{tag1 := {ack, msg1},
                           tag2 := {fail, reason}}}),
    %%
    %% Ack (package 3)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:package(#{tag1 => gen_nbs:msg(DebugPid2, {ack, msg1}),
                                                    tag2 => gen_nbs:msg(DebugPid2, {long_ack, msg2, 2 * ?TIMEOUT})}), ?TIMEOUT}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg1, Sender}}),
    ?WAIT_FOR_MSG({DebugPid2, {long_ack, msg2, Sender}}),
    timer:sleep(3 * ?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, #{tag1 := {ack, msg1},
                           tag2 := {fail, timeout}}}),

    %%
    %% Ack (package 4)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:package(#{tag1 =>
                                                    #{tag11 =>
                                                      gen_nbs:msg(DebugPid2, {ack, msg1}),
                                                      tag12 =>
                                                      gen_nbs:msg(DebugPid2, {ack, msg2})}}), 1}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg1, Sender}}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg2, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, #{tag1 := #{tag11 := {ack, msg1},
                                     tag12 := {ack, msg2}}}}),

    %%
    %% Ack (package 5)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:package(#{tag1 =>
                                                    #{tag11 =>
                                                      gen_nbs:msg(DebugPid2, {long_ack, msg1, 2 * ?TIMEOUT}),
                                                      tag12 =>
                                                      gen_nbs:msg(DebugPid2, {long_ack, msg2, 2 * ?TIMEOUT})}}), ?TIMEOUT}),
    ?WAIT_FOR_MSG({DebugPid2, {long_ack, msg1, Sender}}),
    ?WAIT_FOR_MSG({DebugPid2, {long_ack, msg2, Sender}}),
    timer:sleep(3 * ?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, #{tag1 := #{tag11 := {fail, timeout},
                                     tag12 := {fail, timeout}}}}),

    %%
    %% Manual fail
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {manual_fail, reason})}),
    ?WAIT_FOR_MSG({DebugPid2, {manual_fail, reason, Sender}}),
    ?WAIT_FOR_MSG({Sender, {fail, reason}}),

    %%
    %% Manual ack
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {manual_ack, msg})}),
    ?WAIT_FOR_MSG({DebugPid2, {manual_ack, msg, Sender}}),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),

    %%
    %% Down
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(unknown, {manual_ack, msg})}),
    ?WAIT_FOR_MSG({Sender, {fail, down}}),

    %%
    %% Ack (global name)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg({global, test_global_name}, {ack, msg})}),
    ?WAIT_FOR_MSG({DebugPid4, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),

    %%
    %% Ack (via name)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg({via, global, test_global_name}, {ack, msg})}),
    ?WAIT_FOR_MSG({DebugPid4, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),

    %%
    %% Ack (fully qualified name)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg({test_local_name, node()}, {ack, msg})}),
    ?WAIT_FOR_MSG({DebugPid3, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {ack, msg}}),

    %%
    %% Ack (msg completion fun)
    %%
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {ack, msg}, CompletionFun)}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {ok, {ack, msg}}}),

    %%
    %% Ack (msg completion fun)
    %%
    InvalidCompletionFun = fun(_) -> error(unknown) end,
    gen_nbs:cast(Sender, {transmit, gen_nbs:msg(DebugPid2, {ack, msg}, InvalidCompletionFun)}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {fail, unknown}}),

    %%
    %% Ack (msgs list)
    %%
    gen_nbs:cast(Sender, {transmit, [gen_nbs:msg(DebugPid2, {ack, msg1}),
                                   gen_nbs:msg(DebugPid2, {ack, msg2})]}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg1, Sender}}),
    ?WAIT_FOR_MSG({DebugPid2, {ack, msg2, Sender}}),
    timer:sleep(?TIMEOUT),
    ?WAIT_FOR_MSG({Sender, {ack, msg1}}),
    ?WAIT_FOR_MSG({Sender, {ack, msg2}}),

    gen_nbs:cast(Sender, {transmit, gen_nbs:return({fail, some_return})}),
    ?WAIT_FOR_MSG({Sender, {fail, some_return}}),

    gen_nbs:cast(Sender, {transmit, gen_nbs:return({ack, some_return},
                                                 undefined)}),
    ?WAIT_FOR_MSG({Sender, {ack, some_return}}),

    gen_nbs:cast(Sender, {transmit, gen_nbs:return({fail, some_return},
                                                 CompletionFun)}),
    ?WAIT_FOR_MSG({Sender, {ok, {fail, some_return}}}),
    gen_nbs:stop(Sender),
    gen_nbs:stop(DebugPid2),
    gen_nbs:stop(Pid2),
    gen_nbs:stop(DebugPid3),
    gen_nbs:stop(DebugPid4),

    ok.

test_await(_Config) ->
    {ok, Pid1} = gen_nbs:start(?TEST_MODULE, {notify, self()}, []),
    {ok, Pid2} = gen_nbs:start(?TEST_MODULE, {notify, self()}, []),
    Package1 = gen_nbs:package(#{tag1 => gen_nbs:msg(Pid1, {ack, msg1}),
                                 tag2 => gen_nbs:msg(Pid2, {ack, msg2})}),
    #{tag1 := {ack, msg1},
      tag2 := {ack, msg2}} = gen_nbs:await(Package1),
    ?WAIT_FOR_MSG({Pid1, {ack, msg1, _}}),
    ?WAIT_FOR_MSG({Pid2, {ack, msg2, _}}),

    Package2 = gen_nbs:package(#{tag1 => gen_nbs:msg(Pid1, {ack, msg1}),
                                 tag2 => gen_nbs:msg(invalid_pid, {ack, msg2})}),

    #{tag1 := {ack, msg1},
      tag2 := {fail, down}} = gen_nbs:await(Package2, ?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, {ack, msg1, _}}),

    Package3 = gen_nbs:package(#{tag1 => gen_nbs:msg(Pid1, {ack, msg1}),
                                 tag2 => gen_nbs:msg(Pid2, {long_ack, msg2, 2*?TIMEOUT})}),
    #{tag1 := {ack, msg1},
      tag2 := {fail, timeout}} = gen_nbs:await(Package3, ?TIMEOUT),
    ?WAIT_FOR_MSG({Pid1, {ack, msg1, _}}),
    ?WAIT_FOR_MSG({Pid2, {long_ack, msg2, _}}),

    CompletionFun = fun(#{tag1 := D}) ->  D end,
    Package4 = gen_nbs:package(#{tag1 => gen_nbs:msg(Pid1, {ack, msg1})},
                               CompletionFun),
    {ack, msg1} = gen_nbs:await(Package4),
    ?WAIT_FOR_MSG({Pid1, {ack, msg1, _}}),

    Package5 = gen_nbs:package(#{tag1 => gen_nbs:msg(Pid1, {manual_ack, msg1}),
                                 tag2 => gen_nbs:msg(Pid2, {manual_ack, msg2})}),
    #{tag1 := {ack, msg1},
      tag2 := {ack, msg2}} = gen_nbs:await(Package5),
    ?WAIT_FOR_MSG({Pid1, {manual_ack, msg1, _}}),
    ?WAIT_FOR_MSG({Pid2, {manual_ack, msg2, _}}),

    CompletionFun1 = fun(_) ->  error(unknown) end,
    Msg6 = gen_nbs:msg(Pid1, {ack, msg1}, CompletionFun1),
    {fail, unknown} = gen_nbs:await(Msg6),
    ?WAIT_FOR_MSG({Pid1, {ack, msg1, _}}),

    Package7 = gen_nbs:package(#{tag1 => gen_nbs:msg(Pid1, {ack, msg1}),
                                 tag2 => gen_nbs:package(#{})}),
    #{tag1 := {ack, msg1},
      tag2 := #{}} = gen_nbs:await(Package7),
    ?WAIT_FOR_MSG({Pid1, {ack, msg1, _}}),

    Package6 = gen_nbs:package(#{}),
    #{} = gen_nbs:await(Package6),

    gen_nbs:stop(Pid1),
    gen_nbs:stop(Pid2),
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

