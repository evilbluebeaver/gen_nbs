-module(gen_nbs_refs_SUITE).

-include_lib("common_test/include/ct.hrl").

%% Test server callbacks
-export([suite/0, all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).

-include("gen_nbs_await.hrl").

%% Test cases
-export([test_reg_1/1,
         test_reg_2/1,
         test_use_1/1,
         test_use_2/1,
         test_fail/1]).

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

suite() ->
    [{timetrap,{minutes,10}}].

init_per_suite(Config) ->
    Children= #{tag1 => #ref{ref=ref1,
                             children=#{tag3 => #ref{ref=ref3},
                                        tag4 => #ref{ref=ref4,
                                                     children=#{tag5 => #ref{ref=ref5},
                                                                tag6 => #ref{ref=ref6}}}}},
                tag2 => #ref{ref=ref2}},
    [{children, Children} | Config].

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

groups() ->
    [{reg, [test_reg_1, test_reg_2]},
     {use, [test_use_1, test_use_2]},
     {fail, [test_fail]}].

all() ->
    [{group, reg},
     {group, use},
     {group, fail}].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_reg_1(Config) ->
    Children = proplists:get_value(children, Config),
    Await = #await{tag=master_tag,
                   ref=#ref{ref=master_ref,
                            children=Children}},
    Result = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected = #{master_ref => #ref_ret{tag=master_tag,
                                        children=sets:from_list([ref1, ref2]),
                                        results=#{}},
                 ref1 => #ref_ret{tag=tag1,
                                  parent_ref=master_ref,
                                  children=sets:from_list([ref3, ref4]),
                                  results=#{}},
                 ref2 => #ref_ret{tag=tag2,
                                  parent_ref=master_ref,
                                  children=undefined,
                                  results=undefined},
                 ref3 => #ref_ret{tag=tag3,
                                  parent_ref=ref1,
                                  children=undefined,
                                  results=undefined},
                 ref4 => #ref_ret{tag=tag4,
                                  parent_ref=ref1,
                                  children=sets:from_list([ref5, ref6]),
                                  results=#{}},
                 ref5 => #ref_ret{tag=tag5,
                                  parent_ref=ref4,
                                  children=undefined,
                                  results=undefined},
                 ref6 => #ref_ret{tag=tag6,
                                  parent_ref=ref4,
                                  children=undefined,
                                  results=undefined}},
    Expected = Result,
    ok.

test_reg_2(_Config) ->
    Await = #await{tag=master_tag,
                    ref=#ref{ref=ref1}},
    Result = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected = #{ref1 => #ref_ret{tag=master_tag,
                                   parent_ref=undefined,
                                   children=undefined,
                                   results=undefined}},
    Expected = Result,
    ok.

test_use_1(Config) ->
    Children = proplists:get_value(children, Config),
    CompletionFun = fun(D) -> D end,
    Await = #await{tag=master_tag,
                   timer_ref=timer_ref,
                   ref=#ref{ref=master_ref,
                            completion_fun=CompletionFun,
                            children=Children}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    {ok, Refs} = gen_nbs_refs:use(ack, ok, unknown_ref, Refs),
    {ok, Refs1} = gen_nbs_refs:use(ack, ok, ref6, Refs),
    {ok, Refs2} = gen_nbs_refs:use(ack, ok, ref5, Refs1),
    {ok, Refs3} = gen_nbs_refs:use(ack, ok, ref3, Refs2),
    Result = gen_nbs_refs:use(ack, ok, ref2, Refs3),
    Expected = {ack, #{tag2=> {ack, ok},
                       tag1 => #{tag3 => {ack,ok},
                                 tag4 => #{tag5 => {ack,ok},tag6 => {ack,ok}}}},
                master_tag, timer_ref, #{}},
    Result = Expected,
    ok.

test_use_2(_Config) ->
    Await = #await{tag=master_tag,
                    ref=#ref{ref=ref1}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Result = gen_nbs_refs:use(ack, ok, ref1, Refs),
    Expected = {ack, {ack, ok}, master_tag, undefined, #{}},
    Expected = Result,
    ok.

test_fail(Config) ->
    Children = proplists:get_value(children, Config),
    CompletionFun = fun(D) -> D end,
    Await = #await{tag=master_tag,
                   timer_ref=timer_ref,
                   ref=#ref{ref=master_ref,
                            completion_fun=CompletionFun,
                            children=Children}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Result1 = gen_nbs_refs:use(fail, timeout, master_ref, Refs),
    Expected1 = {ack,#{tag1 =>
                       #{tag3 => {fail,timeout},
                         tag4 => #{tag5 => {fail,timeout},tag6 => {fail,timeout}}},
                       tag2 => {fail,timeout}},
                 master_tag, timer_ref, #{}},
    Result1 = Expected1,

    {ok, Refs1} = gen_nbs_refs:use(ack, ok, ref5, Refs),
    Result2 = gen_nbs_refs:use(fail, timeout, master_ref, Refs1),
    Expected2 = {ack,#{tag1 =>
                       #{tag3 => {fail,timeout},
                         tag4 => #{tag5 => {ack,ok},tag6 => {fail,timeout}}},
                       tag2 => {fail, timeout}},
                 master_tag, timer_ref, #{}},
    Result2 = Expected2,
    ok.
