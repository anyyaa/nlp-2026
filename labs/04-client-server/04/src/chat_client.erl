-module(chat_client).
-export([main/0]).

main() ->
    io:setopts([{encoding, unicode}]),
    case init:get_plain_arguments() of
        [Name | _] -> connect(Name);
        [] ->
            case io:get_line("Nickname (letters, digits, _): ") of
                eof -> halt(1);
                NameLine -> connect(string:trim(NameLine))
            end
    end.

connect(Name) ->
    Nick = unicode:characters_to_binary(Name),
    case chat_protocol:valid_nick(Nick) of
        false ->
            io:format("Invalid nickname. Use 1-16 ASCII letters, digits or _.~n"),
            halt(1);
        true ->
            Options = [binary, {packet, line}, {active, false}],
            case gen_tcp:connect({127,0,0,1}, 5052, Options, 3000) of
                {ok, Socket} ->
                    ok = gen_tcp:send(Socket, <<"NICK ", Nick/binary, "\n">>),
                    case gen_tcp:recv(Socket, 0, 3000) of
                        {ok, <<"OK ", _/binary>> = Reply} ->
                            io:format("~ts", [Reply]),
                            io:format("Type a message. /users lists participants; /quit exits.~n"),
                            start_receiver(Socket),
                            input_loop(Socket);
                        {ok, Reply} ->
                            io:format("~ts", [Reply]),
                            gen_tcp:close(Socket), halt(1);
                        {error, Reason} ->
                            io:format("Server handshake failed: ~p~n", [Reason]),
                            gen_tcp:close(Socket), halt(1)
                    end;
                {error, Reason} ->
                    io:format("Connection failed (~p). Start chat_server first.~n", [Reason]),
                    halt(1)
            end
    end.

start_receiver(Socket) ->
    Pid = spawn(fun() -> receive ready -> receive_loop(Socket) end end),
    ok = gen_tcp:controlling_process(Socket, Pid),
    Pid ! ready.

receive_loop(Socket) ->
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            receive
                {tcp, Socket, Line} ->
                    io:format("~ts", [Line]),
                    receive_loop(Socket);
                {tcp_closed, Socket} ->
                    io:format("~nConnection closed.~n");
                {tcp_error, Socket, Reason} ->
                    io:format("~nNetwork error: ~p~n", [Reason])
            end;
        {error, _} -> ok
    end.

input_loop(Socket) ->
    case io:get_line("> ") of
        eof -> quit(Socket);
        RawLine ->
            Line = string:trim(RawLine),
            case Line of
                "/quit" -> quit(Socket);
                "/users" ->
                    gen_tcp:send(Socket, <<"USERS\n">>),
                    input_loop(Socket);
                "" -> input_loop(Socket);
                _ ->
                    Message = unicode:characters_to_binary(Line),
                    case byte_size(Message) =< 512 of
                        true -> gen_tcp:send(Socket, <<"MSG ", Message/binary, "\n">>);
                        false -> io:format("Message too long (max 512 bytes).~n")
                    end,
                    input_loop(Socket)
            end
    end.

quit(Socket) ->
    gen_tcp:send(Socket, <<"QUIT\n">>),
    timer:sleep(150),
    gen_tcp:close(Socket),
    halt(0).
