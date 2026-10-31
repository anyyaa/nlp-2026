
exception Parse_error of int * string

type parser = {
  input : string;
  mutable pos : int;
}

let current p =
  if p.pos < String.length p.input then
    Some p.input.[p.pos]
  else
    None

let advance p =
  p.pos <- p.pos + 1

let rec skip_spaces p =
  match current p with
  | Some (' ' | '\t' | '\n' | '\r') ->
      advance p;
      skip_spaces p
  | _ -> ()

let rec parse_expression p =
  let value = parse_term p in
  let rec loop acc =
    skip_spaces p;
    match current p with
    | Some '+' ->
        advance p;
        let rhs = parse_term p in
        loop (acc + rhs)
    | Some '-' ->
        advance p;
        let rhs = parse_term p in
        loop (acc - rhs)
    | _ -> acc
  in
  loop value

and parse_term p =
  let value = parse_unary p in
  let rec loop acc =
    skip_spaces p;
    match current p with
    | Some '*' ->
        advance p;
        let rhs = parse_unary p in
        loop (acc * rhs)
    | Some '/' ->
        let op_pos = p.pos + 1 in
        advance p;
        let rhs = parse_unary p in
        if rhs = 0 then
          raise (Parse_error (op_pos, "division by zero"));
        loop (acc / rhs)
    | _ -> acc
  in
  loop value

and parse_unary p =
  skip_spaces p;
  match current p with
  | Some '-' ->
      advance p;
      let value = parse_unary p in
      -value
  | _ -> parse_primary p

and parse_primary p =
  skip_spaces p;
  match current p with
  | Some '(' ->
      advance p;
      let value = parse_expression p in
      skip_spaces p;
      (match current p with
       | Some ')' ->
           advance p;
           value
       | _ ->
           raise (Parse_error
             (p.pos + 1, "expected ')'")))
  | Some c when c >= '0' && c <= '9' ->
      let start = p.pos in
      while
        p.pos < String.length p.input &&
        p.input.[p.pos] >= '0' &&
        p.input.[p.pos] <= '9'
      do
        advance p
      done;
      (try
         int_of_string
           (String.sub p.input start (p.pos - start))
       with Failure _ ->
         raise (Parse_error
           (start + 1, "invalid integer")))
  | _ ->
      raise (Parse_error
        (p.pos + 1, "expected number or '('"))

let evaluate expression =
  let p = { input = expression; pos = 0 } in
  let result = parse_expression p in
  skip_spaces p;
  if p.pos < String.length p.input then
    raise (Parse_error
      (p.pos + 1, "unexpected character"));
  result

let test expression =
  try
    let result = evaluate expression in
    Printf.printf "%s => %d\n" expression result
  with
  | Parse_error (position, message) ->
      Printf.printf
        "%s => error at position %d: %s\n"
        expression position message

let () =
  let expressions = [
    "2*(3+4)";
    "-(-5)";
    "2+3*4";
    "(2+3)*4";
    "7/-2";
    "10/3";
    "5--2";
    "3/0";
    "2*(3+4";
    "2+3abc";
    "1 2";
    "3+";
    "()"
  ] in
  List.iter test expressions
