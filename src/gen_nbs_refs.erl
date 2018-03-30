-module(gen_nbs_refs).

-export([new/0,
         use/4,
         reg/2]).

-include("gen_nbs_await.hrl").

-type refs() :: #{reference() => #ref_ret{}}.
-spec new() -> refs().
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

-spec use(Result :: ack | fail, Data :: term(),
          Ref :: reference(), Refs :: refs()) -> {ok, refs()} |
                                                 {ack, msg_result(), term(), reference() | undefined, refs()}.
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
    Fun = fun(ChildRef, ChildRef, Acc) ->
                  fill_children_results(Result, Reason, ChildRef, Acc)
          end,
    {Results1, Refs1} = maps:fold(Fun, {Results, Refs}, Children),
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
            {Results#{Tag => {Result, Reason}}, Refs1};
        {#ref_ret{tag=Tag,
                  children=Children,
                  results=ChildrenResults}, Refs1} ->
            Fun = fun(ChildRef, ChildRef, Acc) ->
                          fill_children_results(Result, Reason, ChildRef, Acc)
                  end,
            {ChildrenResults2, Refs2} = maps:fold(Fun, {ChildrenResults, Refs1}, Children),
            {Results#{Tag => ChildrenResults2}, Refs2}
    end.

use_parent(ChildResult, ChildRef, ChildTag, Ref, Refs) ->
    Ret=#ref_ret{children=Children,
                 results=Results} = maps:get(Ref, Refs),
    Children1 = maps:remove(ChildRef, Children),
    Results1 = Results#{ChildTag => ChildResult},
    case maps:size(Children1) of
        0 ->
            Refs1 = maps:remove(Ref, Refs),
            use_result(Results1, Ref, Ret, Refs1);
        _ ->
            Ret1 = Ret#ref_ret{children=Children1,
                               results=Results1},
            Refs1 = Refs#{Ref => Ret1},
            {ok, Refs1}
    end.

results_map(undefined) ->
    undefined;
results_map(_) ->
    #{}.

children_map(undefined) ->
    undefined;
children_map(Children) ->
    Fun = fun(_Tag, #ref{ref=Ref}, Refs) ->
                  Refs#{Ref => Ref}
          end,
    maps:fold(Fun, maps:new(), Children).

-spec reg(await() | [await()], refs()) -> refs().
reg(Awaits, Refs) when is_list(Awaits) ->
    lists:foldl(fun reg/2, Refs, Awaits);

reg(#await{tag=Tag,
           timer_ref=TimerRef,
           ref=#ref{ref=Ref,
                    completion_fun=CompletionFun,
                    children=Children}}, Refs) ->
    RefRet = #ref_ret{tag=Tag,
                      timer_ref=TimerRef,
                      completion_fun=CompletionFun,
                      children=children_map(Children),
                      results=results_map(Children)},
    RefsAcc = Refs#{Ref => RefRet},
    reg_children(Ref, Children, RefsAcc).

reg_children(_Ref, undefined, RefsAcc) ->
    RefsAcc;

reg_children(Ref, Children, RefsAcc) ->
    Fun = fun(InnerTag, #ref{ref=InnerRef,
                             completion_fun=CompletionFun,
                             children=InnerChildren},
              InnerRefsAcc) ->
                  InnerRefsAcc1 = InnerRefsAcc#{InnerRef =>
                                                #ref_ret{tag=InnerTag,
                                                         parent_ref=Ref,
                                                         completion_fun=CompletionFun,
                                                         children=children_map(InnerChildren),
                                                         results=results_map(InnerChildren)}},
                  reg_children(InnerRef, InnerChildren, InnerRefsAcc1)
          end,
    maps:fold(Fun, RefsAcc, Children).

