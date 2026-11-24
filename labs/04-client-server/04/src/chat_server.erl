-module(chat_server).
-export([main/0, start/1, stop/1]).

main() ->
    case start(5052) of
        {ok, Server, Port} ->
            io:format("Chat server listening on 127.0.0.1:~B~n", [Port]),
            io:format("Open two client terminals. Press Ctrl+C to stop.~n"),
            receive stop -> stop(Server) end;
        {error, Reason} ->
            io:format("Server error: ~p~n", [Reason]),
            halt(1)
    end.

start(Port) when is_integer(Port), Port >= 0, Port =< 65535 ->
    Options = [binary, {packet, line}, {active, false},
               {reuseaddr, true}, {ip, {127,0,0,1}}, {packet_size, 2048}],
    case gen_tcp:listen(Port, Options) of
        {ok, Listen} ->
            {ok, {_, ActualPort}} = inet:sockname(Listen),
            Hub = spawn(fun() -> hub_loop(#{}) end),
            Acceptor = spawn(fun() -> accept_loop(Listen, Hub) end),
            {ok, {Listen, Hub, Acceptor}, ActualPort};
        {error, Reason} -> {error, Reason}
    end.

stop({Listen, Hub, _Acceptor}) ->
    gen_tcp:close(Listen),
    Hub ! stop,
    ok.

accept_loop(Listen, Hub) ->
    case gen_tcp:accept(Listen) of
        {ok, Socket} ->
            Worker = spawn(fun() ->
                receive ready -> socket_loop(Socket, Hub, undefined) end
            end),
            case gen_tcp:controlling_process(Socket, Worker) of
                ok -> Worker ! ready;
                {error, _} -> gen_tcp:close(Socket), exit(Worker, kill)
            end,
            accept_loop(Listen, Hub);
        {error, closed} -> ok;
        {error, Reason} ->
            io:format("Accept error: ~p~n", [Reason]),
            ok
    end.

socket_loop(Socket, Hub, Nick) ->
    case inet:setopts(Socket, [{active, once}]) of
        ok -> socket_wait(Socket, Hub, Nick);
        {error, _} -> Hub ! {leave, self()}, gen_tcp:close(Socket)
    end.

socket_wait(Socket, Hub, Nick) ->
    receive
        {tcp, Socket, Line} ->
            case handle_line(Socket, Hub, Nick, Line) of
                {continue, NewNick} -> socket_loop(Socket, Hub, NewNick);
                stop -> Hub ! {leave, self()}, gen_tcp:close(Socket)
            end;
        {deliver, Message} ->
            case gen_tcp:send(Socket, Message) of
                ok -> socket_wait(Socket, Hub, Nick);
                {error, _} -> Hub ! {leave, self()}, gen_tcp:close(Socket)
            end;
        {tcp_closed, Socket} -> Hub ! {leave, self()};
        {tcp_error, Socket, _} -> Hub ! {leave, self()};
        shutdown -> gen_tcp:close(Socket)
    end.

handle_line(Socket, Hub, Nick, Line) ->
    case chat_protocol:parse(Line) of
        {error, Reason} ->
            gen_tcp:send(Socket, <<"ERROR ", Reason/binary, "\n">>),
            {continue, Nick};
        {nick, NewNick} when Nick =:= undefined ->
            Hub ! {join, self(), NewNick},
            receive
                {join_reply, ok} ->
                    gen_tcp:send(Socket, <<"OK Welcome ", NewNick/binary, "\n">>),
                    {continue, NewNick};
                {join_reply, taken} ->
                    gen_tcp:send(Socket, <<"ERROR Nickname already taken\n">>),
                    {continue, undefined}
            end;
        {nick, _} ->
            gen_tcp:send(Socket, <<"ERROR Nickname already set\n">>),
            {continue, Nick};
        quit ->
            gen_tcp:send(Socket, <<"BYE\n">>),
            stop;
        users when Nick =:= undefined ->
            gen_tcp:send(Socket, <<"ERROR Set nickname first\n">>),
            {continue, Nick};
        users ->
            Hub ! {users, self()},
            receive
                {users_reply, Names} ->
                    Joined = iolist_to_binary(lists:join(<<",">>, Names)),
                    gen_tcp:send(Socket, <<"USERS ", Joined/binary, "\n">>)
            end,
            {continue, Nick};
        {msg, _} when Nick =:= undefined ->
            gen_tcp:send(Socket, <<"ERROR Set nickname first\n">>),
            {continue, Nick};
        {msg, Message} ->
            Hub ! {say, self(), Nick, Message},
            {continue, Nick}
    end.

hub_loop(Users) ->
    receive
        {join, Pid, Nick} ->
            case maps:is_key(Nick, Users) of
                true -> Pid ! {join_reply, taken}, hub_loop(Users);
                false ->
                    io:format("JOIN ~ts~n", [Nick]),
                    Pid ! {join_reply, ok},
                    broadcast(Users, <<"INFO ", Nick/binary, " joined\n">>),
                    hub_loop(maps:put(Nick, Pid, Users))
            end;
        {say, Pid, Nick, Message} ->
            case maps:find(Nick, Users) of
                {ok, Pid} ->
                    io:format("MSG ~ts: ~ts~n", [Nick, Message]),
                    broadcast(Users, <<"MSG ", Nick/binary, ": ", Message/binary, "\n">>);
                _ -> ok
            end,
            hub_loop(Users);
        {users, Pid} ->
            Pid ! {users_reply, lists:sort(maps:keys(Users))},
            hub_loop(Users);
        {leave, Pid} ->
            Matches = [Name || {Name, Worker} <- maps:to_list(Users), Worker =:= Pid],
            case Matches of
                [Name | _] ->
                    io:format("LEFT ~ts~n", [Name]),
                    Remaining = maps:remove(Name, Users),
                    broadcast(Remaining, <<"INFO ", Name/binary, " left\n">>),
                    hub_loop(Remaining);
                [] -> hub_loop(Users)
            end;
        stop ->
            lists:foreach(fun(Pid) -> Pid ! shutdown end, maps:values(Users)),
            ok
    end.

broadcast(Users, Message) ->
    lists:foreach(fun(Pid) -> Pid ! {deliver, Message} end, maps:values(Users)).
