-module(gen_nbs_refs).

-export([new/0,
         use/4,
         reg/2,
         refs/1]).

-include("gen_nbs_await.hrl").

-record(await_ref, {timer_ref, tag, master_ref, child_refs, results=#{}}).

new() ->
    #{}.

refs(Refs) ->
    L = maps:to_list(Refs),
    Fun = fun({_, #await_ref{child_refs=undefined}},
              {_, _}) ->
                  true;
             (_, _) ->
                  false
          end,
    {Keys, _} = lists:unzip(lists:sort(Fun, L)),
    Keys.

use(Result, Reason, Ref, Refs) when is_reference(Ref) ->
    case maps:find(Ref, Refs) of
        error ->
            {ok, Refs};
        {ok, AwaitRef} ->
            Refs1 = maps:remove(Ref, Refs),
            use(Result, Reason, Ref, AwaitRef, Refs1)
    end.

use(Result, Reason, _Ref, #await_ref{tag=Tag,
                                     timer_ref=TimerRef,
                                     master_ref=undefined,
                                     child_refs=undefined}, Refs) ->
    {ack, {Result, Reason}, Tag, TimerRef, Refs};

use(fail, Reason, _Ref, #await_ref{timer_ref=TimerRef,
                                   tag=Tag,
                                   master_ref=undefined,
                                   child_refs=ChildRefs,
                                   results=Results}, Refs) ->
    Fun = fun(ChildRef, ChildTag, {RefAcc, ResultsAcc}) ->
                  {maps:remove(ChildRef, RefAcc),
                   maps:put(ChildTag, {fail, Reason}, ResultsAcc)}
          end,
    {Refs1, Results1} = maps:fold(Fun, {Refs, Results}, ChildRefs),
    {ack, Results1, Tag, TimerRef, Refs1};

use(Result, Reason, Ref, #await_ref{master_ref=MasterRef,
                                    child_refs=undefined,
                                    tag=Tag}, Refs) ->
    MasterRefValue=#await_ref{child_refs=ChildRefs,
                              tag=MasterTag,
                              master_ref=undefined,
                              timer_ref=TimerRef,
                              results=Results} = maps:get(MasterRef, Refs),
    Results1 = maps:put(Tag, {Result, Reason}, Results),
    ChildRefs1 = maps:remove(Ref, ChildRefs),
    case maps:size(ChildRefs1) of
        0 ->
            {ack, Results1, MasterTag, TimerRef, maps:remove(MasterRef, Refs)};
        _ ->

            Refs1 = maps:update(MasterRef,
                                MasterRefValue#await_ref{child_refs=ChildRefs1,
                                                         results=Results1},
                                Refs),
            {ok, Refs1}
    end.


reg(Awaits, Refs) when is_list(Awaits) ->
    lists:foldl(fun(Await, Acc) -> reg(Await, Acc) end, Refs, Awaits);

reg(#await{master_ref=MasterRef,
           tag=Tag,
           child_refs=ChildRefs,
           timer_ref=TimerRef}, Refs) ->
    Refs1 = maps:put(MasterRef, #await_ref{timer_ref=TimerRef,
                                          tag=Tag,
                                          child_refs=ChildRefs}, Refs),
    ChildFun = fun(Ref, ChildTag, Acc) ->
                       maps:put(Ref, #await_ref{tag=ChildTag,
                                                master_ref=MasterRef},
                                Acc)
               end,
    case ChildRefs of
        undefined ->
            Refs1;
        ChildRefs ->
            maps:fold(ChildFun, Refs1, ChildRefs)
    end.

