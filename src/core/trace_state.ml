(** W3C Trace State - https://www.w3.org/TR/trace-context/#tracestate-header *)

type t = (string * string) list

let empty : t = []

let is_valid_key (k : string) : bool =
  let n = String.length k in
  if n < 1 || n > 256 then
    false
  else (
    let ok =
      ref
        (match k.[0] with
        | 'a' .. 'z' -> true
        | _ -> false)
    in
    let i = ref 1 in
    while !ok && !i < n do
      (match k.[!i] with
      | 'a' .. 'z' | '0' .. '9' | '_' | '-' | '*' | '/' -> ()
      | _ -> ok := false);
      incr i
    done;
    !ok
  )

let is_valid_value (v : string) : bool =
  let n = String.length v in
  if n < 1 || n > 256 then
    false
  else (
    let ok = ref (v.[0] <> ' ' && v.[n - 1] <> ' ') in
    let i = ref 0 in
    while !ok && !i < n do
      let code = Char.code v.[!i] in
      if code < 0x20 || code > 0x7e || v.[!i] = ',' || v.[!i] = '=' then
        ok := false;
      incr i
    done;
    !ok
  )

let get (self : t) (key : string) : string option = List.assoc_opt key self

let set (self : t) (key : string) (value : string) : t =
  if not (is_valid_key key) then
    invalid_arg (Printf.sprintf "Trace_state.set: invalid key %S" key);
  if not (is_valid_value value) then
    invalid_arg (Printf.sprintf "Trace_state.set: invalid value %S" value);
  let rest = List.filter (fun (k, _) -> k <> key) self in
  (key, value) :: rest

let delete (self : t) (key : string) : t =
  List.filter (fun (k, _) -> k <> key) self

let encoded_length (self : t) : int =
  match self with
  | [] -> 0
  | _ ->
    let n = List.length self in
    let sum =
      List.fold_left
        (fun acc (k, v) -> acc + String.length k + 1 + String.length v)
        0 self
    in
    sum + n - 1

let to_w3c_string (self : t) : string =
  match self with
  | [] -> ""
  | _ ->
    let buf = Buffer.create (encoded_length self) in
    List.iteri
      (fun i (k, v) ->
        if i > 0 then Buffer.add_char buf ',';
        Buffer.add_string buf k;
        Buffer.add_char buf '=';
        Buffer.add_string buf v)
      self;
    Buffer.contents buf

let of_w3c_string (s : string) : (t, string) result =
  if s = "" then
    Ok []
  else (
    let parts = String.split_on_char ',' s in
    let pairs =
      List.filter_map
        (fun part ->
          let part = String.trim part in
          match String.index_opt part '=' with
          | None -> None
          | Some i ->
            let k = String.sub part 0 i in
            let v = String.sub part (i + 1) (String.length part - i - 1) in
            if is_valid_key k && is_valid_value v then
              Some (k, v)
            else
              None)
        parts
    in
    Ok pairs
  )
