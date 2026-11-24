-module(chat_tests).
-export([main/0]).

check(Name, Good) ->
    Count = get(tests_total),
    Passed = get(tests_passed),
    put(tests_total, Count + 1),
    case Good of
        true ->
            io:format("~s: PASS~n", [Name]),
            put(tests_passed, Passed + 1);
        false -> io:format("~s: FAIL~n", [Name])
    end.

send(Socket, Data) ->
    ok = gen_tcp:send(Socket, Data).

receive_equals(Socket, Expected) ->
    case gen_tcp:recv(Socket, 0, 2000) of
        {ok, Expected} -> true;
        {ok, Actual} ->
            io:format("  Expected ~p, got ~p~n", [Expected, Actual]),
            false;
        {error, Reason} ->
            io:format("  Receive failed: ~p~n", [Reason]),
            false
    end.

connect(Port) ->
    gen_tcp:connect({127,0,0,1}, Port,
                    [binary, {packet, line}, {active, false}], 3000).

run_protocol_checks() ->
    check("Valid nickname", chat_protocol:valid_nick(<<"Anna_1">>)),
    check("Reject nickname with spaces", not chat_protocol:valid_nick(<<"Anna B">>)),
    check("Reject long nickname", not chat_protocol:valid_nick(<<"12345678901234567">>)),
    check("Parse nickname", chat_protocol:parse(<<"NICK Anna\n">>) =:= {nick, <<"Anna">>}),
    check("Parse chat message", chat_protocol:parse(<<"MSG Hello\n">>) =:= {msg, <<"Hello">>}),
    Unicode = unicode:characters_to_binary([1055,1088,1080,1074,1077,1090]),
    check("Parse UTF-8 message", chat_protocol:parse(<<"MSG ", Unicode/binary, "\n">>) =:= {msg, Unicode}),
    check("Parse users command", chat_protocol:parse(<<"USERS\n">>) =:= users),
    check("Parse quit command", chat_protocol:parse(<<"QUIT\n">>) =:= quit),
    check("Reject empty message", element(1, chat_protocol:parse(<<"MSG \n">>)) =:= error),
    TooLong = binary:copy(<<"x">>, 513),
    check("Reject oversized message", element(1, chat_protocol:parse(<<"MSG ", TooLong/binary>>)) =:= error),
    check("Strip CRLF", chat_protocol:strip_eol(<<"abc\r\n">>) =:= <<"abc">>).

run_network_checks() ->
    {ok, Server, Port} = chat_server:start(0),
    try
        {ok, Alice} = connect(Port),
        try
            {ok, Stranger} = connect(Port),
            try
                send(Stranger, <<"MSG hello\n">>),
                check("Must join before messaging",
                      receive_equals(Stranger, <<"ERROR Set nickname first\n">>)),
                send(Alice, <<"NICK Anna\n">>),
                check("First client welcomed", receive_equals(Alice, <<"OK Welcome Anna\n">>)),
                send(Stranger, <<"NICK Anna\n">>),
                check("Duplicate nickname rejected",
                      receive_equals(Stranger, <<"ERROR Nickname already taken\n">>))
            after
                gen_tcp:close(Stranger)
            end,
            {ok, Boris} = connect(Port),
            try
                send(Boris, <<"NICK Boris\n">>),
                check("Second client welcomed", receive_equals(Boris, <<"OK Welcome Boris\n">>)),
                check("Join notification reaches first client",
                      receive_equals(Alice, <<"INFO Boris joined\n">>)),
                send(Alice, <<"MSG Hello everyone!\n">>),
                check("Message reaches sender",
                      receive_equals(Alice, <<"MSG Anna: Hello everyone!\n">>)),
                check("Message reaches second client",
                      receive_equals(Boris, <<"MSG Anna: Hello everyone!\n">>)),
                send(Alice, <<"USERS\n">>),
                check("List active users", receive_equals(Alice, <<"USERS Anna,Boris\n">>)),
                send(Boris, <<"UNKNOWN\n">>),
                check("Unknown command gets error",
                      receive_equals(Boris, <<"ERROR Unknown command\n">>)),
                Unicode = unicode:characters_to_binary([1055,1088,1080,1074,1077,1090]),
                send(Boris, <<"MSG ", Unicode/binary, "\n">>),
                UnicodeReply = <<"MSG Boris: ", Unicode/binary, "\n">>,
                check("UTF-8 reaches sender", receive_equals(Boris, UnicodeReply)),
                check("UTF-8 reaches other client", receive_equals(Alice, UnicodeReply)),
                send(Boris, <<"QUIT\n">>),
                check("Quit acknowledged", receive_equals(Boris, <<"BYE\n">>)),
                check("Leave notification reaches other client",
                      receive_equals(Alice, <<"INFO Boris left\n">>)),
                send(Alice, <<"USERS\n">>),
                check("Users list updated after leave",
                      receive_equals(Alice, <<"USERS Anna\n">>))
            after
                gen_tcp:close(Boris)
            end
        after
            gen_tcp:close(Alice)
        end
    after
        chat_server:stop(Server)
    end.

main() ->
    put(tests_total, 0),
    put(tests_passed, 0),
    run_protocol_checks(),
    try
        run_network_checks()
    catch
        Class:Reason:Stack ->
            io:format("Network test error: ~p:~p~n~p~n", [Class, Reason, Stack])
    end,
    Passed = get(tests_passed),
    Total = get(tests_total),
    io:format("~nPassed: ~B/~B~n", [Passed, Total]),
    case Passed =:= 25 andalso Total =:= 25 of
        true -> halt(0);
        false -> halt(1)
    end.
