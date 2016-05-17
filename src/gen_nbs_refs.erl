-module(gen_nbs_refs).

-export([new/0,
         use/4,
         reg/2]).

-include("gen_nbs_await.hrl").

-record(master_ref, {timer_ref, tag, child_refs, results=#{}}).

-record(plain_ref, {timer_ref, tag}).

-record(child_ref, {tag, master_ref}).

new() ->
    #{}.

use(Result, Reason, Ref, Refs) when is_reference(Ref) ->
    case maps:find(Ref, Refs) of
        error ->
            {ok, Refs};
        {ok, FRef} ->
            use(Result, Reason, FRef, Ref, Refs)
    end.

use(Result, Reason, #plain_ref{tag=Tag, timer_ref=TimerRef}, Ref, Refs) ->
    {ack, {Result, Reason}, Tag, TimerRef, maps:remove(Ref, Refs)};

use(fail, Reason, #master_ref{timer_ref=TimerRef,
                                tag=Tag,
                                child_refs=ChildRefs,
                                results=Results}, Ref, Refs) ->
    NRefs = maps:remove(Ref, Refs),
    Fun = fun(ChildRef, ChildTag, {RefAcc, ResultsAcc}) ->
                  {maps:remove(ChildRef, RefAcc),
                   maps:put(ChildTag, {fail, Reason}, ResultsAcc)}
          end,
    {NRefs1, Results1} = maps:fold(Fun, {NRefs, Results}, ChildRefs),
    {ack, Results1, Tag, TimerRef, NRefs1};

use(Result, Reason, #child_ref{master_ref=MasterRef, tag=Tag}, Ref, Refs) ->
    NRefs = maps:remove(Ref, Refs),
    MasterRefValue=#master_ref{child_refs=ChildRefs,
                               tag=MasterTag,
                               timer_ref=TimerRef,
                               results=Results} = maps:get(MasterRef, NRefs),
    Results1 = maps:put(Tag, {Result, Reason}, Results),
    ChildRefs1 = maps:remove(Ref, ChildRefs),
    case maps:size(ChildRefs1) of
        0 ->
            {ack, Results1, MasterTag, TimerRef, maps:remove(MasterRef, NRefs)};
        _ ->

            NRefs1 = maps:update(MasterRef,
                                 MasterRefValue#master_ref{child_refs=ChildRefs1,
                                                           results=Results1},
                                 NRefs),
            {ok, NRefs1}
    end.

reg(Awaits, Refs)  when is_list(Awaits) ->
    lists:foldl(fun reg_fold/2, Refs, Awaits);

reg(Await, Refs) ->
    reg([Await], Refs).

reg_fold(?AWAIT(MasterRef, Refs, TimerRef, Tag), Acc) when is_map(Refs) ->
    Acc1 = maps:put(MasterRef, #master_ref{timer_ref=TimerRef,
                                           tag=Tag,
                                           child_refs=Refs}, Acc),
    maps:fold(fun(Ref, ChildTag, RAcc) ->
                        maps:put(Ref,
                                 #child_ref{tag=ChildTag,
                                            master_ref=MasterRef}, RAcc)
                end, Acc1, Refs);
reg_fold(?AWAIT(Ref, TimerRef, Tag), Acc) ->
    maps:put(Ref, #plain_ref{timer_ref=TimerRef,
                             tag=Tag}, Acc).


