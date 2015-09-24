
%
% erl_echo.erl
% A simple telnet echo server which prints back to the user whatever
% they sent. Whenever the user may want to exit, he/she has the
% possibility of closing the connection by typing "exit".
%
% This code is Public Domain.
%

-module(erl_echo).
-export([start_server/0, connect/1, recv_loop/1]).
-compile(export_all).

% The port used to listen for incoming connections. Although the telnet
% protocol specifies port number 23, port 2323 is used because it
% require no privileges for association.
-define(LISTEN_PORT, 2323).

% TCP options.
-define(TCP_OPTS, [
  binary,
  {packet, raw},
  {nodelay, true},
  {reuseaddr, true},
  {active, once}]).

% The message that the users will receive after connecting.
-define(WELCOME_MESSAGE, [
  "Welcome! This is an \x1b[32mecho server\x1b[0m.\r\n",
  "Anything you write will be printed right back at you.\r\n"]).

% What to prefix the users' input lines with.
-define(LINE_PREFIX, "> ").

%
% start_server/0: starts listening for incoming connections on the port
% specified by LISTEN_PORT
%
start_server() ->
  case gen_tcp:listen(?LISTEN_PORT, ?TCP_OPTS) of
    {ok, Listen} -> spawn(?MODULE, connect, [Listen]),
                    io:format("~p Server Started.~n", [erlang:localtime()]);
    Error -> io:format("Error: ~p~n", [Error])
  end.

%
% connect/1: accepts a connection, greeting the user and then jumps
% into recv_loop
%
connect(Listen) ->
  {ok, Socket} = gen_tcp:accept(Listen),
  inet:setopts(Socket, ?TCP_OPTS),
  spawn_link(erl_echo, connect, [Listen]),

  % Won't suppress go-ahead
  gen_tcp:send(Socket, <<255, 252, 3>>),

  % Won't echo
  gen_tcp:send(Socket, <<255, 252, 1>>),

  gen_tcp:send(Socket, ?WELCOME_MESSAGE),
  gen_tcp:send(Socket, ?LINE_PREFIX),
  recv_loop(Socket),
  gen_tcp:close(Socket).

%
% handle_do/2: handles a 'DO' telnet negotiation request
%
handle_do(Socket, Code) ->
  case Code of
    _ ->
      io:format("~p ~p DO ~p~n", [inet:peername(Socket), erlang:localtime(), Code])
  end.

%
% handle_dont/2: handles a 'DONT' telnet negotiation request
%
handle_dont(Socket, Code) ->
  case Code of
    _ ->
      io:format("~p ~p DON'T ~p~n", [inet:peername(Socket), erlang:localtime(), Code])
  end.
  
%
% handle_will/2: handles a 'WILL' telnet negotiation request
%
handle_will(Socket, Code) ->
  case Code of
    _ ->
      io:format("~p ~p WILL ~p~n", [inet:peername(Socket), erlang:localtime(), Code])
  end.

%
% handle_wont/2: handles a 'WONT' telnet negotiation request
%
handle_wont(Socket, Code) ->
  case Code of
    _ ->
      io:format("~p ~p WON'T ~p~n", [inet:peername(Socket), erlang:localtime(), Code])
  end.

%
% handle_negotiation/2: handles a telnet negotiation, parsing the entire
% message if there are more than one requests present; be warned that, if
% there is other data besides negotiation codes, the data will be dropped
%
handle_negotiation(Socket, Data) ->
  case Data of
    % IAC WILL
    <<255, 251, What:8, Rest/binary>> ->
      handle_will(Socket, What),
      handle_negotiation(Socket, Rest);

    % IAC WONT
    <<255, 252, What:8, Rest/binary>> ->
      handle_wont(Socket, What),
      handle_negotiation(Socket, Rest);

    % IAC DO
    <<255, 253, What:8, Rest/binary>> ->
      handle_do(Socket, What),
      handle_negotiation(Socket, Rest);

    % IAC DONT
    <<255, 254, What:8, Rest/binary>> ->
      handle_dont(Socket, What),
      handle_negotiation(Socket, Rest);

    <<_/binary>> ->
      ok;
    <<>> ->
      ok
  end.

%
% handle_data/2: handles data incoming from a connection -- checks
% whether the user wants to close the session, and handles negotiation
% messages by passing them further to handle_negotiation/2
%
handle_data(Socket, Data) ->
  io:format("~p ~p ~p~n", [inet:peername(Socket), erlang:localtime(), Data]),
  case Data of
    % "exit\r\n" closes the session.
    <<"exit\r\n">> ->
      io:format("~p ~p Closed.~n", [inet:peername(Socket), erlang:localtime()]),
      gen_tcp:close(Socket);

    % IAC -- Interpret As Command.
    <<255, _Rest/binary>> ->
      handle_negotiation(Socket, Data),
      recv_loop(Socket);

    % send back all other data received.
    _ ->
      gen_tcp:send(Socket, [Data, "> "]),
      recv_loop(Socket)
  end.

%
% recv_loop/1: handles a connection's event loop
%
recv_loop(Socket) ->
  inet:setopts(Socket, [{active, once}]),
  receive
    {tcp, Socket, Data} ->
      handle_data(Socket, Data);
    {tcp_closed, Socket} ->
      io:format("~p Client Disconnected.~n", [erlang:localtime()])
  end.

