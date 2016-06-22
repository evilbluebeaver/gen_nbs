-module(gen_nbs_refs).

-export([new/0,
         use/4,
         reg/2]).

-include("gen_nbs_await.hrl").

new() ->
    #{}.

complete(undefined, Data) ->
    Data;
complete(CompleteFun, Data) ->
    CompleteFun(Data).

use(Result, Data, Ref, Refs) ->
    case maps:find(Ref, Refs) of
        error ->
            {ok, Refs};
        {ok, Ret} ->
            use(Result, Data, Ref, Ret, Refs)
    end.

use(Result, Data, Ref,
    #ref_ret{tag=Tag,
             master=MasterRef,
             complete_fun=CompleteFun,
             children=undefined,
             results=undefined},
    Refs) ->
    CompleteResult = complete(CompleteFun, {Result, Data}),
    Refs1 = maps:remove(Ref, Refs),
    use_master(CompleteResult, Ref, Tag, MasterRef, Refs1);

use(fail, Reason, Ref,
    #ref_ret{tag=Tag,
             master=undefined,
             children=Children,
             results=Results}, Refs) ->
    Refs1 = maps:remove(Ref, Refs),
    Fun = fun(ChildRef, Acc) ->
                  fill_children_results(Reason, ChildRef, Acc)
          end,
    {Results2, Refs2} = lists:foldl(Fun, {Results, Refs1}, sets:to_list(Children)),
    {ack, Results2, Tag, Ref, Refs2};

use(_Result, _Data, _Ref, _Ret, Refs) ->
    {ok, Refs}.

fill_children_results(Reason, Ref, {Results, Refs}) ->
    case maps:get(Ref, Refs) of
        #ref_ret{tag=Tag,
                 children=undefined} ->
            Refs1 = maps:remove(Ref, Refs),
            {maps:put(Tag, {fail, Reason}, Results), Refs1};
        #ref_ret{tag=Tag,
                 children=Children,
                 results=ChildrenResults} ->
            Refs1 = maps:remove(Ref, Refs),
            Fun = fun(ChildRef, Acc) ->
                          fill_children_results(Reason, ChildRef, Acc)
                  end,
            {ChildrenResults2, Refs2} = lists:foldl(Fun, {ChildrenResults, Refs1},
                                                    sets:to_list(Children)),
            {maps:put(Tag, ChildrenResults2, Results), Refs2}
    end.

use_master(ChildResult, ChildRef, ChildTag, Ref, Refs) ->
    Ret=#ref_ret{tag=Tag,
                 master=MasterRef,
                 children=Children,
                 results=Results,
                 complete_fun=CompleteFun} = maps:get(Ref, Refs),
    Children1 = sets:del_element(ChildRef, Children),
    Results1 = maps:put(ChildTag, ChildResult, Results),
    case sets:size(Children1) of
        0 ->
            Refs1 = maps:remove(Ref, Refs),
            CompleteResult = complete(CompleteFun, Results1),
            case MasterRef of
                undefined ->
                    {ack, Results1, Tag, Ref, Refs1};
                MasterRef ->
                    use_master(CompleteResult, Ref, Tag, MasterRef, Refs1)
            end;
        _ ->
            Ret1 = Ret#ref_ret{children=Children1,
                               results=Results1},
            Refs1 = maps:put(Ref, Ret1, Refs),
            {ok, Refs1}
    end.

reg(#await{tag=Tag,
           msg=#msg{ref=MasterRef,
                    complete_fun=CompleteFun,
                    children=Children}}, OldRefs) ->
    Acc = #{MasterRef => #ref_ret{tag=Tag,
                                  complete_fun=CompleteFun,
                                  children=make_children(Children),
                                  results=make_results(Children)}},
    FlatChildren = make_flat(MasterRef, Children, Acc),
    maps:merge(FlatChildren, OldRefs).


make_flat(_Master, undefined, Result) ->
    Result;

make_flat(Master, Refs, Result) ->
    Fun = fun(Tag, #msg{ref=Ref,
                        complete_fun=CompleteFun,
                        children=Children}, Acc) ->
                  Acc1 = maps:put(Ref, #ref_ret{tag=Tag,
                                                master=Master,
                                                complete_fun=CompleteFun,
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
    Fun = fun(_Tag, #msg{ref=Ref}, Acc) ->
                  sets:add_element(Ref, Acc)
          end,
    maps:fold(Fun, sets:new(), Children).

