-record(await, {master_ref :: reference(),
                tag :: term(),
                complete_fun :: fun((term()) -> term()),
                timer_ref :: reference() | undefined,
                child_refs :: #{term() => reference()} | undefined}).

-type await() :: #await{}.

