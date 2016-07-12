-module(gen_nbs_refs).

-export([new/0,
         use/4,
         reg/2]).

-include("gen_nbs_await.hrl").

new() ->
    #{}.

complete(undefined, Data) ->
    Data;
complete(CompletionFun, Data) ->
    try
        CompletionFun(Data)
    catch
        Kind:Reason ->
            {Kind, Reason}
    end.

use(Result, Data, Ref, Refs) ->
    case maps:take(Ref, Refs) of
        error ->
            {ok, Refs};
        {Ret, Refs1} ->
            use(Result, Data, Ref, Ret, Refs1)
    end.

use(Result, Data, Ref,
    Ret=#ref_ret{children=undefined,
             results=undefined},
    Refs) ->
    use_result({Result, Data}, Ref, Ret, Refs);

use(fail, Reason, _Ref,
    #ref_ret{tag=Tag,
             parent_ref=undefined,
             timer_ref=TimerRef,
             children=Children,
             results=Results}, Refs) ->
    Fun = fun(ChildRef, Acc) ->
                  fill_children_results(Reason, ChildRef, Acc)
          end,
    {Results1, Refs1} = lists:foldl(Fun, {Results, Refs}, sets:to_list(Children)),
    {ack, Results1, Tag, TimerRef, Refs1}.

use_result(Results, Ref, #ref_ret{tag=Tag,
                                  timer_ref=TimerRef,
                                  parent_ref=ParentRef,
                                  completion_fun=CompletionFun}, Refs) ->
    CompleteResult = complete(CompletionFun, Results),
    case ParentRef of
        undefined ->
            {ack, CompleteResult, Tag, TimerRef, Refs};
        ParentRef ->
            use_parent(CompleteResult, Ref, Tag, ParentRef, Refs)
    end.

fill_children_results(Reason, Ref, {Results, Refs}) ->
    case maps:take(Ref, Refs) of
        {#ref_ret{tag=Tag,
                 children=undefined}, Refs1} ->
            {maps:put(Tag, {fail, Reason}, Results), Refs1};
        {#ref_ret{tag=Tag,
                 children=Children,
                 results=ChildrenResults}, Refs1} ->
            Fun = fun(ChildRef, Acc) ->
                          fill_children_results(Reason, ChildRef, Acc)
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

reg(#await{tag=Tag,
           timer_ref=TimerRef,
           ref=#ref{ref=ParentRef,
                    completion_fun=CompletionFun,
                    children=Children}}, OldRefs) ->
    Acc = #{ParentRef => #ref_ret{tag=Tag,
                                  timer_ref=TimerRef,
                                  completion_fun=CompletionFun,
                                  children=make_children(Children),
                                  results=make_results(Children)}},
    FlatChildren = make_flat(ParentRef, Children, Acc),
    maps:merge(FlatChildren, OldRefs).

make_flat(_Parent, undefined, Result) ->
    Result;

make_flat(Parent, Refs, Result) ->
    Fun = fun(Tag, #ref{ref=Ref,
                        completion_fun=CompletionFun,
                        children=Children}, Acc) ->
                  Acc1 = maps:put(Ref, #ref_ret{tag=Tag,
                                                parent_ref=Parent,
                                                completion_fun=CompletionFun,
                                                children=make_children(Children),
                                                results = make_results(Children)},
                          Acc),
                  make_flat(Ref, Children, Acc1)
          end,
    maps:fold(Fun, Result, Refs).


make_results(undefined) ->
    undefined;
make_results(_) ->
    #{}.

make_children(undefined) ->
    undefined;
make_children(Children) ->
    Fun = fun(_Tag, #ref{ref=Ref}, Acc) ->
                  sets:add_element(Ref, Acc)
          end,
    maps:fold(Fun, sets:new(), Children).

