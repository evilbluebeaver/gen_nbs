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
    Config.

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
     {use, [test_use_1, test_use_2, test_fail, test_completion_fun_error]}].

all() ->
    [{group, reg},
     {group, use}].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

test_reg_1(_Config) ->
    MasterRef = make_ref(),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    Ref3 = make_ref(),
    Ref4 = make_ref(),
    Ref5 = make_ref(),
    Ref6 = make_ref(),
    Children= #{tag1 => #ref{ref=Ref1,
                             children=#{tag3 => #ref{ref=Ref3},
                                        tag4 => #ref{ref=Ref4,
                                                     children=#{tag5 => #ref{ref=Ref5},
                                                                tag6 => #ref{ref=Ref6}}}}},
                tag2 => #ref{ref=Ref2}},
    Await = #await{tag=master_tag,
                   ref=#ref{ref=MasterRef,
                            children=Children}},
    ExpectedRefs = #{MasterRef => #ref_ret{tag=master_tag,
                                            children=sets:from_list([Ref1, Ref2]),
                                            results=#{}},
                     Ref1 => #ref_ret{tag=tag1,
                                      parent_ref=MasterRef,
                                      children=sets:from_list([Ref3, Ref4]),
                                      results=#{}},
                     Ref2 => #ref_ret{tag=tag2,
                                      parent_ref=MasterRef,
                                      children=undefined,
                                      results=undefined},
                     Ref3 => #ref_ret{tag=tag3,
                                      parent_ref=Ref1,
                                      children=undefined,
                                      results=undefined},
                     Ref4 => #ref_ret{tag=tag4,
                                      parent_ref=Ref1,
                                      children=sets:from_list([Ref5, Ref6]),
                                      results=#{}},
                     Ref5 => #ref_ret{tag=tag5,
                                      parent_ref=Ref4,
                                      children=undefined,
                                      results=undefined},
                     Ref6 => #ref_ret{tag=tag6,
                                      parent_ref=Ref4,
                                      children=undefined,
                                      results=undefined}},
    ExpectedRefs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_reg_2(_Config) ->
    Ref1 = make_ref(),
    Await = #await{tag=master_tag,
                   ref=#ref{ref=Ref1}},
    ExpectedRefs = #{Ref1 => #ref_ret{tag=master_tag,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined}},
    ExpectedRefs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    ok.

test_reg_3(_Config) ->
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    Await1 = #await{tag=master_tag1,
                    ref=#ref{ref=Ref1}},
    Await2 = #await{tag=master_tag2,
                    ref=#ref{ref=Ref2}},
    ExpectedRefs = #{Ref1 => #ref_ret{tag=master_tag1,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined},
                     Ref2 => #ref_ret{tag=master_tag2,
                                      parent_ref=undefined,
                                      children=undefined,
                                      results=undefined}},
    ExpectedRefs = gen_nbs_refs:reg([Await1, Await2], gen_nbs_refs:new()),
    ok.

test_use_1(_Config) ->
    MasterRef = make_ref(),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    Ref3 = make_ref(),
    Ref4 = make_ref(),
    Ref5 = make_ref(),
    Ref6 = make_ref(),
    Children= #{tag1 => #ref{ref=Ref1,
                             children=#{tag3 => #ref{ref=Ref3},
                                        tag4 => #ref{ref=Ref4,
                                                     children=#{tag5 => #ref{ref=Ref5},
                                                                tag6 => #ref{ref=Ref6}}}}},
                tag2 => #ref{ref=Ref2}},
    CompletionFun = fun(D) -> D end,
    Await = #await{tag=master_tag,
                   timer_ref=timer_ref,
                   ref=#ref{ref=MasterRef,
                            completion_fun=CompletionFun,
                            children=Children}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    {ok, Refs} = gen_nbs_refs:use(ack, ok, unknown_ref, Refs),
    {ok, Refs1} = gen_nbs_refs:use(ack, ok, Ref6, Refs),
    {ok, Refs2} = gen_nbs_refs:use(ack, ok, Ref5, Refs1),
    {ok, Refs3} = gen_nbs_refs:use(ack, ok, Ref3, Refs2),
    Expected = {ack, #{tag2=> {ack, ok},
                       tag1 => #{tag3 => {ack,ok},
                                 tag4 => #{tag5 => {ack,ok},tag6 => {ack,ok}}}},
                master_tag, timer_ref, #{}},
    Expected = gen_nbs_refs:use(ack, ok, Ref2, Refs3),
    ok.

test_use_2(_Config) ->
    Ref1 = make_ref(),
    Await = #await{tag=master_tag,
                   ref=#ref{ref=Ref1}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected = {ack, {ack, ok}, master_tag, undefined, #{}},
    Expected = gen_nbs_refs:use(ack, ok, Ref1, Refs),
    ok.

test_fail(_Config) ->
    MasterRef = make_ref(),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    Ref3 = make_ref(),
    Ref4 = make_ref(),
    Ref5 = make_ref(),
    Ref6 = make_ref(),
    Children= #{tag1 => #ref{ref=Ref1,
                             children=#{tag3 => #ref{ref=Ref3},
                                        tag4 => #ref{ref=Ref4,
                                                     children=#{tag5 => #ref{ref=Ref5},
                                                                tag6 => #ref{ref=Ref6}}}}},
                tag2 => #ref{ref=Ref2}},
    CompletionFun = fun(D) -> D end,
    Await = #await{tag=master_tag,
                   timer_ref=timer_ref,
                   ref=#ref{ref=MasterRef,
                            completion_fun=CompletionFun,
                            children=Children}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected1 = {ack,#{tag1 =>
                       #{tag3 => {fail,timeout},
                         tag4 => #{tag5 => {fail,timeout},tag6 => {fail,timeout}}},
                       tag2 => {fail,timeout}},
                 master_tag, timer_ref, #{}},
    Expected1 = gen_nbs_refs:use(fail, timeout, MasterRef, Refs),

    {ok, Refs1} = gen_nbs_refs:use(ack, ok, Ref5, Refs),
    Expected2 = {ack,#{tag1 =>
                       #{tag3 => {fail,timeout},
                         tag4 => #{tag5 => {ack,ok},tag6 => {fail,timeout}}},
                       tag2 => {fail, timeout}},
                 master_tag, timer_ref, #{}},
    Expected2 = gen_nbs_refs:use(fail, timeout, MasterRef, Refs1),
    ok.

test_completion_fun_error(_Config) ->
    CompletionFun = fun(_) -> error(some_error) end,
    Ref1 = make_ref(),
    Await = #await{tag=master_tag,
                   ref=#ref{ref=Ref1,
                            completion_fun=CompletionFun}},
    Refs = gen_nbs_refs:reg(Await, gen_nbs_refs:new()),
    Expected = {ack, {fail, some_error}, master_tag, undefined, #{}},
    Expected = gen_nbs_refs:use(ack, ok, Ref1, Refs),
    ok.
