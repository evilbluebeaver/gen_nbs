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
         test_reg_3/1,
         test_reg_completed_1/1,
         test_reg_completed_2/1,
         test_reg_undefined_ref_1/1,
         test_reg_undefined_ref_2/1,
         test_use_1/1,
         test_use_2/1,
         test_fail/1,
         test_completion_fun_error/1]).

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
    [{reg, [test_reg_1, test_reg_2, test_reg_3]},
     {reg_completed, [test_reg_completed_1, test_reg_completed_2]},
     {reg_undefined_ref, [test_reg_undefined_ref_1, test_reg_undefined_ref_2]},
     {use, [test_use_1, test_use_2, test_fail, test_completion_fun_error]}].

all() ->
    [{group, reg},
     {group, reg_completed},
     {group, reg_undefined_ref},
     {group, use}].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_reg_1(Config) ->
    Children = proplists:get_value(children, Config),
    Await = #await{tag=master_tag,
                   ref=#ref{ref=master_ref,
                            children=Children}},
    ExpectedRefs = #{master_ref => #ref_ret{tag=master_tag,
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
    ExpectedCompleted = [],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_reg_2(_Config) ->
    Await = #await{tag=master_tag,
                   ref=#ref{ref=ref1}},
    ExpectedRefs = #{ref1 => #ref_ret{tag=master_tag,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined}},
    ExpectedCompleted = [],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_reg_3(_Config) ->
    Await1 = #await{tag=master_tag1,
                    ref=#ref{ref=ref1}},
    Await2 = #await{tag=master_tag2,
                    ref=#ref{ref=ref2}},
    ExpectedRefs = #{ref1 => #ref_ret{tag=master_tag1,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined},
                     ref2 => #ref_ret{tag=master_tag2,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined}},
    ExpectedCompleted = [],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg([Await1, Await2], gen_nbs_refs:new()),
    ok.

test_reg_completed_1(_Config) ->
    Await = #await{tag=master_tag,
                   ref=#ref{ref=master_ref,
                            children=#{}}},
    ExpectedRefs = #{master_ref => #ref_ret{tag=master_tag,
                                            parent_ref=undefined,
                                            children=undefined,
                                            results=undefined}},
    ExpectedCompleted = [{master_ref, {ack, #{}}}],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_reg_completed_2(_Config) ->
    Await1 = #await{tag=master_tag1,
                    ref=#ref{ref=ref1, children=#{}}},
    Await2 = #await{tag=master_tag2,
                    ref=#ref{ref=ref2}},
    ExpectedRefs = #{ref1 => #ref_ret{tag=master_tag1,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined},
                     ref2 => #ref_ret{tag=master_tag2,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined}},
    ExpectedCompleted = [{ref1, {ack, #{}}}],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg([Await1, Await2], gen_nbs_refs:new()),
    ok.

test_reg_undefined_ref_1(_Config) ->
    Await = #await{tag=master_tag,
                   ref=#ref{ref=master_ref,
                            return=some_return}},
    ExpectedRefs = #{master_ref => #ref_ret{tag=master_tag,
                                            parent_ref=undefined,
                                            children=undefined,
                                            results=undefined}},
    ExpectedCompleted = [{master_ref, some_return}],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_reg_undefined_ref_2(_Config) ->
    Await = #await{tag=master_tag,
                   ref=#ref{ref=master_ref,
                            children=#{child_tag => #ref{ref=child_ref,
                                                     return=some_return}}}},
    ExpectedRefs = #{master_ref => #ref_ret{tag=master_tag,
                                            parent_ref=undefined,
                                            children=sets:from_list([child_ref]),
                                            results=#{}},
                     child_ref => #ref_ret{tag=child_tag,
                                           parent_ref=master_ref,
                                           children=undefined,
                                           results=undefined}},
    ExpectedCompleted = [{child_ref, some_return}],
    Expected = {ExpectedRefs, ExpectedCompleted},
    Expected = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_use_1(Config) ->
    Children = proplists:get_value(children, Config),
    CompletionFun = fun(D) -> D end,
    Await = #await{tag=master_tag,
                   timer_ref=timer_ref,
                   ref=#ref{ref=master_ref,
                            completion_fun=CompletionFun,
                            children=Children}},
    {Refs, []} = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    {ok, Refs} = gen_nbs_refs:use(ack, ok, unknown_ref, Refs),
    {ok, Refs1} = gen_nbs_refs:use(ack, ok, ref6, Refs),
    {ok, Refs2} = gen_nbs_refs:use(ack, ok, ref5, Refs1),
    {ok, Refs3} = gen_nbs_refs:use(ack, ok, ref3, Refs2),
    Expected = {ack, #{tag2=> {ack, ok},
                       tag1 => #{tag3 => {ack,ok},
                                 tag4 => #{tag5 => {ack,ok},tag6 => {ack,ok}}}},
                master_tag, timer_ref, #{}},
    Expected = gen_nbs_refs:use(ack, ok, ref2, Refs3),
    ok.

test_use_2(_Config) ->
    Await = #await{tag=master_tag,
                   ref=#ref{ref=ref1}},
    {Refs, []} = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected = {ack, {ack, ok}, master_tag, undefined, #{}},
    Expected = gen_nbs_refs:use(ack, ok, ref1, Refs),
    ok.

test_fail(Config) ->
    Children = proplists:get_value(children, Config),
    CompletionFun = fun(D) -> D end,
    Await = #await{tag=master_tag,
                   timer_ref=timer_ref,
                   ref=#ref{ref=master_ref,
                            completion_fun=CompletionFun,
                            children=Children}},
    {Refs, []} = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected1 = {ack,#{tag1 =>
                       #{tag3 => {fail,timeout},
                         tag4 => #{tag5 => {fail,timeout},tag6 => {fail,timeout}}},
                       tag2 => {fail,timeout}},
                 master_tag, timer_ref, #{}},
    Expected1 = gen_nbs_refs:use(fail, timeout, master_ref, Refs),

    {ok, Refs1} = gen_nbs_refs:use(ack, ok, ref5, Refs),
    Expected2 = {ack,#{tag1 =>
                       #{tag3 => {fail,timeout},
                         tag4 => #{tag5 => {ack,ok},tag6 => {fail,timeout}}},
                       tag2 => {fail, timeout}},
                 master_tag, timer_ref, #{}},
    Expected2 = gen_nbs_refs:use(fail, timeout, master_ref, Refs1),
    ok.

test_completion_fun_error(_Config) ->
    CompletionFun = fun(_) -> error(some_error) end,
    Await = #await{tag=master_tag,
                   ref=#ref{ref=ref1,
                            completion_fun=CompletionFun}},
    {Refs, []} = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected = {ack, {fail, some_error}, master_tag, undefined, #{}},
    Expected = gen_nbs_refs:use(ack, ok, ref1, Refs),
    ok.
