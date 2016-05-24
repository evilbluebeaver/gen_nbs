-record(await, {master_ref :: reference(),
                tag :: term(),
                timer_ref :: reference() | undefined,
                child_refs :: #{term() => reference()} | undefined}).

-type await() :: #await{}.

