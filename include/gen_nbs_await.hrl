-define(AWAIT(MasterRef, Refs, Timer, Tag),
        {await, MasterRef, Refs, Timer, Tag}).
-define(AWAIT(Ref, Timer, Tag),
        {await, Ref, Timer, Tag}).
-type timer() :: reference() | undefined.
-type await_single() :: {await, reference(), timer(), term()}.
-type await_multiple() :: {await, reference(), [reference()], term()}.
-type await_r() :: await_single() | await_multiple().
-type await() :: await_r() | [await_r()].

