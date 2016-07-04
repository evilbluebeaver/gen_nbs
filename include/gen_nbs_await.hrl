-record(msg, {dest, payload, completion_fun}).

-record(package, {children :: #{term() => #package{} | #msg{}},
                  completion_fun :: fun()}).

-record(ref, {ref :: term(),
              children :: #{term() => #ref{}},
              completion_fun :: fun((term()) -> term())}).

-record(await, {tag :: term(),
                timer_ref :: reference(),
                ref :: #ref{}}).


-type await() :: #await{}.


-record(ref_ret, {tag,
                  parent_ref,
                  timer_ref,
                  completion_fun,
                  children,
                  results}).


