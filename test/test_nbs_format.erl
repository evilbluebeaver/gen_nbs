-module(test_nbs_format).

-export([init/1,
         terminate/2,
         format_status/2]).

init({format_status, Fun}) ->
    {ok, {format_status, Fun}}.

terminate(_Reason, _State) ->
    ok.

format_status(_, [_, {format_status, Fun}]) ->
    Fun().

