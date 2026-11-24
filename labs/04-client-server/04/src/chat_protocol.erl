-module(chat_protocol).
-export([parse/1, valid_nick/1, strip_eol/1]).

strip_eol(Data) when is_binary(Data), byte_size(Data) > 0 ->
    case binary:last(Data) of
        10 ->
            WithoutLf = binary:part(Data, 0, byte_size(Data) - 1),
            case WithoutLf of
                <<>> -> <<>>;
                _ ->
                    case binary:last(WithoutLf) of
                        13 -> binary:part(WithoutLf, 0, byte_size(WithoutLf) - 1);
                        _ -> WithoutLf
                    end
            end;
        _ -> Data
    end;
strip_eol(Data) when is_binary(Data) -> Data.

valid_nick(Nick) when is_binary(Nick) ->
    Size = byte_size(Nick),
    Size >= 1 andalso Size =< 16 andalso
    lists:all(fun(C) ->
        (C >= $a andalso C =< $z) orelse
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse C =:= $_
    end, binary_to_list(Nick));
valid_nick(_) -> false.

parse(Line0) when is_binary(Line0) ->
    Line = strip_eol(Line0),
    case Line of
        <<"NICK ", Nick/binary>> ->
            case valid_nick(Nick) of
                true -> {nick, Nick};
                false -> {error, <<"Invalid nickname (1-16 letters, digits or _)">>}
            end;
        <<"MSG ", Message/binary>> ->
            case byte_size(Message) of
                0 -> {error, <<"Empty message">>};
                N when N > 512 -> {error, <<"Message too long">>};
                _ ->
                    case unicode:characters_to_list(Message, utf8) of
                        Chars when is_list(Chars) -> {msg, Message};
                        _ -> {error, <<"Invalid UTF-8 message">>}
                    end
            end;
        <<"USERS">> -> users;
        <<"QUIT">> -> quit;
        _ -> {error, <<"Unknown command">>}
    end.
