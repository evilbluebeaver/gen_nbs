-record(msg, {ref :: term(),
              dest :: term(),
              children :: #{term() => #msg{}},
              complete_fun :: fun((term()) -> term())}).

-record(await, {tag :: term(),
                msg :: #msg{}}).

-type await() :: #await{}.


-record(ref_ret, {tag,
                  master,
                  complete_fun,
                  children,
                  results}).


