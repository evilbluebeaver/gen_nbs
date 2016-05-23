-record(await, {master_ref :: reference(),
                timer_ref :: reference() | undefined,
                child_refs :: #{term() => reference()} | undefined}).

-type await() :: #{Tag :: term() => [#await{}] | #await{}}.

