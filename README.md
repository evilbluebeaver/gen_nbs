[![Build Status](https://travis-ci.org/evilbluebeaver/gen_nbs.svg?branch=master)](https://travis-ci.org/evilbluebeaver/gen_nbs)
[![codecov](https://codecov.io/gh/evilbluebeaver/gen_nbs/branch/master/graph/badge.svg)](https://codecov.io/gh/evilbluebeaver/gen_nbs)

gen_nbs
=====

Non-blocking server behaviour

Basic template
-----

	-module(gen_nbs).

	-behaviour(gen_nbs).

	%% API
	-export([start_link/0]).

	%% gen_nbs callbacks
	-export([init/1,
		 handle_msg/3,
		 handle_ack/3,
		 handle_cast/2,
		 handle_info/2,
		 code_change/3,
		 terminate/2]).

	%%%===================================================================
	%%% API
	%%%===================================================================
	start_link() ->
		gen_nbs:start_link(?MODULE, [], []).

	%%%===================================================================
	%%% gen_nbs callbacks
	%%%===================================================================
	init([]) ->
		{ok, #{}}.

	handle_msg(_Msg, From, State) ->
		Ack = ok,
		{ack, From, Ack, State}.

	handle_ack(_Ack, _Tag, State) ->
		{ok, State}.

	handle_cast(_Msg, State) ->
		{ok, State}.

	handle_info(_Info, State) ->
		{ok, State}.

	code_change(_OldVsn, State, _Extra) ->
		{ok, State}.

	terminate(_Reason, _State) ->
		ok.

	%%%===================================================================
	%%% Internal functions
	%%%===================================================================

Short description of callbacks
-----
Module:init/1 acts just like gen_server's version.

Module:handle_msg/3 handles incoming messages. Possible returned values are:
- {ack, From, Ack, State [, Timeout | hibernate]}
- {fail, From, Reason, State, [, Timeout | hibernate]}
- {await, Await, State [, Timeout | hibernate]}
- {ok, State, [, Timeout | hibernate]}
- {stop, Reason, State}

Module:handle_ack/3 handles responses to outgoing messages. Possible returned values are the same. 'Ack' parameter can be one of the following:
- {ack, Data} if another process has responded with 'ack'
- {fail, Reason} if another process has responded with 'fail'
- {fail, timeout} if timeout of sending message to another process had triggered before another process responded of another process hasn't responded
- Recursive map for packaged messages


Module:handle_cast/3, Module:handle_info/3, Module:code_change/3 acts just like in gen_server except for returning values the same as shown above.

How to prepare messages
-----
Single message:

	gen_nbs:msg(Recepient, Payload)
	or
	gen_nbs:msg(Recepient, Payload, CompletionFun)

Prepare a single message with 'Payload' to be sent to the 'Recepient'. 'CompletionFun' can be used to make some actions after response has been received but before 'handle_ack'. It will be called in sender process. Useful for closing connections and so on.

Return:

	gen_nbs:return(Payload)
	or
	gen_nbs:return(Payload, CompletionFun)

Immediately return a value without sending it anywhere.

Package:

	gen_nbs:package(Recepient, Msgs)
	or
	gen_nbs:package(Recepient, Msgs, CompletionFun)

Prepare a package of messages to be sent to their corrresponding recepients. 'Msgs' is a recursive map where each key is an arbitrary identifier and its corresponding value is an another recursive map of messages or single message or return. 'handle_ack' will be called after all the responses (or timeouts). 'CompletionFun' acts the same way.


How to send messages
-----

There are two ways of sending message.

If current process is a gen_nbs process you can send message this way:

	Await = gen_nbs:transmit(Msg, Tag)
	or
	Await = gen_nbs:transmit(Msg, Tag, Timeout)

This 'await' value should be given to {await, Await, State} return value of a callback. After the response is received 'handle_ack' will be called with corresponding response and tag. Tag is just any term you can use to identify message.

You can use {await, Awaits, State} with list of awaits then multiple 'handle_ack' will be called each for one await.


If current process is not a gen_nbs process you should use this:
	gen_nbs:await(Msg)

It blocks until a response is received and return it as a function result.


How to call gen_server from inside the gen_nbs
-----
Use gen_nbs:safe_call to avoid certain pitfalls while calling gen_server from inside the gen_nbs



Miscellaneous examples
-----

	handle_msg(load_data, From, Connection) ->
	    CompletionFun = fun({ack, Data}) ->
					{ack, jiffy:decode(Data)};
				({fail, Reason}) ->
					{fail, Reason}
					end,
		Msg = case Connection of
				undefined ->
					gen_nbs:return({fail, no_connection});
				Connection ->
					gen_nbs:msg(Connection, load_data)
			  end,
		Tag = {load_tag, From},
		Await = gen_nbs:transmit(Msg, Tag),
		{await, Await, Connection}.

	handle_ack({ack, Data}, {load_tag, From}, _Connection) ->
		{ack, From, Data, Connection};
	handle_ack({fail, Reason}, {load_msg, From}, _Connection) ->
		io:format("Error ~p while loading data ~n", [Reason]),
		{fail, From, Reason, Connection).

... more examples will be added later
