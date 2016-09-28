-module(gen_nbs_refs).

-export([new/0,
         use/4,
         reg/2]).

-include("gen_nbs_await.hrl").

new() ->
    #{}.

complete(undefined, Data) ->
    {ok, Data};
complete(CompletionFun, Data) ->
    try
        {ok, CompletionFun(Data)}
    catch
        _Kind:Reason ->
            {fail, Reason}
    end.

use(Result, Data, Ref, Refs) ->
    case maps:take(Ref, Refs) of
        error ->
            {ok, Refs};
        {Ret, Refs1} ->
            true = demonitor(Ref, [flush]),
            use(Result, Data, Ref, Ret, Refs1)
    end.

use(Result, Data, Ref,
    Ret=#ref_ret{children=undefined, results=undefined}, Refs) ->
    use_result({Result, Data}, Ref, Ret, Refs);

use(Result, Reason, Ref,
    RefRet = #ref_ret{children=Children,
                      results=Results}, Refs) ->
    Fun = fun(ChildRef, Acc) ->
                  fill_children_results(Result, Reason, ChildRef, Acc)
          end,
    {Results1, Refs1} = lists:foldl(Fun, {Results, Refs}, sets:to_list(Children)),
    use_result(Results1, Ref, RefRet, Refs1).

use_result(Results, Ref, #ref_ret{tag=Tag,
                                  timer_ref=TimerRef,
                                  parent_ref=ParentRef,
                                  completion_fun=CompletionFun}, Refs) ->
    CompleteResult = case complete(CompletionFun, Results) of
                         {ok, C} ->
                             C;
                         {fail, Reason} ->
                             {fail, Reason}
                     end,
    case ParentRef of
        undefined ->
            {ack, CompleteResult, Tag, TimerRef, Refs};
        ParentRef ->
            use_parent(CompleteResult, Ref, Tag, ParentRef, Refs)
    end.

fill_children_results(Result, Reason, Ref, {Results, Refs}) ->
    true = demonitor(Ref, [flush]),
    case maps:take(Ref, Refs) of
        {#ref_ret{tag=Tag,
                  children=undefined, results=undefined}, Refs1} ->
            {maps:put(Tag, {Result, Reason}, Results), Refs1};
        {#ref_ret{tag=Tag,
                  children=Children,
                  results=ChildrenResults}, Refs1} ->
            Fun = fun(ChildRef, Acc) ->
                          fill_children_results(Result, Reason, ChildRef, Acc)
                  end,
            {ChildrenResults2, Refs2} = lists:foldl(Fun, {ChildrenResults, Refs1},
                                                    sets:to_list(Children)),
            {maps:put(Tag, ChildrenResults2, Results), Refs2}
    end.

use_parent(ChildResult, ChildRef, ChildTag, Ref, Refs) ->
    Ret=#ref_ret{children=Children,
                 results=Results} = maps:get(Ref, Refs),
    Children1 = sets:del_element(ChildRef, Children),
    Results1 = maps:put(ChildTag, ChildResult, Results),
    case sets:size(Children1) of
        0 ->
            Refs1 = maps:remove(Ref, Refs),
            use_result(Results1, Ref, Ret, Refs1);
        _ ->
            Ret1 = Ret#ref_ret{children=Children1,
                               results=Results1},
            Refs1 = maps:put(Ref, Ret1, Refs),
            {ok, Refs1}
    end.

results_map(undefined) ->
    undefined;
results_map(_) ->
    #{}.

children_set(undefined) ->
    undefined;
children_set(Children) ->
    Fun = fun(_Tag, #ref{ref=Ref}, Acc) ->
                  sets:add_element(Ref, Acc)
          end,
    maps:fold(Fun, sets:new(), Children).

reg(Awaits, Refs) when is_list(Awaits) ->
    Fun = fun(Ref, {RefsAcc, CompletedAcc}) ->
                  {RefsAcc1, Completed} = reg(Ref, RefsAcc),
                  CompletedAcc1 = CompletedAcc ++ Completed,
                  {RefsAcc1, CompletedAcc1}
          end,
    lists:foldl(Fun, {Refs, []}, Awaits);

reg(#await{tag=Tag,
           timer_ref=TimerRef,
           ref=#ref{ref=Ref,
                    return=Return,
                    completion_fun=CompletionFun,
                    children=Children}}, Refs) ->
    RefRet = #ref_ret{tag=Tag,
                      timer_ref=TimerRef,
                      completion_fun=CompletionFun,
                      children=children_set(Children),
                      results=results_map(Children)},
    RefsAcc = maps:put(Ref, RefRet, Refs),
    CompletedRefsAcc = case Return of
                           undefined ->
                               [];
                           Return ->
                               [{Ref, Return}]
                       end,
    reg_children(Ref, Children, RefsAcc, CompletedRefsAcc).

reg_children(_Ref, undefined, RefsAcc, CompletedRefsAcc) ->
    {RefsAcc, CompletedRefsAcc};
reg_children(Ref, Children, RefsAcc, CompletedRefsAcc)
  when map_size(Children) == 0 ->
    CompletedRefsAcc1 = [{Ref, {ack, #{}}} | CompletedRefsAcc],
    {RefsAcc, CompletedRefsAcc1};

reg_children(Ref, Children, RefsAcc, CompletedRefsAcc) ->
    Fun = fun(InnerTag, #ref{ref=InnerRef,
                             return=InnerReturn,
                             completion_fun=CompletionFun,
                             children=InnerChildren},
              {InnerRefsAcc, InnerCompletedAcc}) ->
                  InnerRefsAcc1 = maps:put(InnerRef,
                                           #ref_ret{tag=InnerTag,
                                                    parent_ref=Ref,
                                                    completion_fun=CompletionFun,
                                                    children=children_set(InnerChildren),
                                                    results=results_map(InnerChildren)},
                                           InnerRefsAcc),
                  InnerCompletedAcc1 = case InnerReturn of
                                           undefined ->
                                               InnerCompletedAcc;
                                           InnerReturn ->
                                               [{InnerRef, InnerReturn} | InnerCompletedAcc]
                                       end,
                  reg_children(InnerRef, InnerChildren, InnerRefsAcc1, InnerCompletedAcc1)
          end,
    maps:fold(Fun, {RefsAcc, CompletedRefsAcc}, Children).

