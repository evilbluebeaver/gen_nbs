-define(AWAIT(MasterRef, Refs, Timer, Tag),
        {'$gen_await', MasterRef, Refs, Timer, Tag}).
-define(AWAIT(Ref, Timer, Tag),
        {'$gen_await', Ref, Timer, Tag}).
