
-type msg_result() :: {ack, term()} | {fail | term()}.
-type package_result() :: #{term => msg_result() | package_result()}.
-type completion_fun() :: undefined | fun((msg_result() | package_result()) -> msg_result()).

-record(return, {payload :: term(), completion_fun :: completion_fun()}).

-record(msg, {dest, payload :: term(), completion_fun :: completion_fun()}).

-record(package, {children :: #{term() => #package{} | #msg{}},
                  completion_fun :: completion_fun()}).

-record(ref, {ref :: term(),
              children :: #{term() => #ref{}} | undefined,
              completion_fun :: completion_fun()}).

-record(await, {tag :: term(),
                timer_ref :: reference(),
                ref :: #ref{}}).


-type await() :: #await{}.
-type msg() :: #{term() => msg()} | #msg{} | #package{} | #return{}.

-record(ref_ret, {tag :: term(),
                  parent_ref :: reference() | undefined,
                  timer_ref :: reference() | undefined,
                  completion_fun :: completion_fun(),
                  children :: maps:map() | undefined,
                  results :: #{} | undefined}).


