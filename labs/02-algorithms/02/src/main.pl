
at_index(0, [H|_], H).
at_index(N, [_|T], X) :-
    N > 0,
    N1 is N - 1,
    at_index(N1, T, X).

seen(X, [X|_]).
seen(X, [_|T]) :-
    seen(X, T).

reverse_list([], Acc, Acc).
reverse_list([H|T], Acc, Result) :-
    reverse_list(T, [H|Acc], Result).

free_cell(Maze, (X, Y)) :-
    X >= 0,
    Y >= 0,
    at_index(Y, Maze, Row),
    at_index(X, Row, 0).

move((X, Y), (NX, Y)) :-
    NX is X + 1.

move((X, Y), (X, NY)) :-
    NY is Y + 1.

move((X, Y), (NX, Y)) :-
    NX is X - 1.

move((X, Y), (X, NY)) :-
    NY is Y - 1.

dfs(_, Finish, Finish, Visited, Path) :-
    reverse_list(Visited, [], Path).

dfs(Maze, Current, Finish, Visited, Path) :-
    move(Current, Next),
    free_cell(Maze, Next),
    \+ seen(Next, Visited),
    dfs(Maze, Next, Finish, [Next|Visited], Path).

solve(Maze, Start, Finish, Path) :-
    free_cell(Maze, Start),
    free_cell(Maze, Finish),
    dfs(Maze, Start, Finish, [Start], Path),
    !.

test(Name, Maze, Start, Finish) :-
    nl,
    write('--- '),
    write(Name),
    write(' ---'),
    nl,
    ( solve(Maze, Start, Finish, Path) ->
        write('Path: '),
        write(Path),
        nl
    ;
        write('Path not found'),
        nl
    ).

main :-
    Maze1 = [
        [0, 0, 1, 0, 0],
        [1, 0, 1, 0, 1],
        [0, 0, 0, 0, 0],
        [0, 1, 1, 1, 0],
        [0, 0, 0, 0, 0]
    ],
    test('Normal maze', Maze1, (0, 0), (4, 4)),

    Maze2 = [
        [0, 0, 0],
        [0, 1, 0],
        [0, 0, 0]
    ],
    test('Maze with cycle', Maze2, (0, 0), (2, 2)),

    Maze3 = [
        [0, 1, 0],
        [1, 1, 0],
        [0, 0, 0]
    ],
    test('No path', Maze3, (0, 0), (2, 2)),

    test('Same start and finish',
         Maze1, (0, 0), (0, 0)).

:- initialization(main).
