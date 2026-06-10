(** Parsing of a reasonable subset of TEF (the "Trace Event Format", aka the
    Chrome trace event format) as emitted by
    {{:https://github.com/c-cube/ocaml-trace} ocaml-trace}'s [trace.tef]
    backend.

    This module is pure: it turns a string (a JSON array, or newline-delimited
    JSON objects) into a list of {!t}. Events it does not understand are simply
    dropped. *)

type value = Opentelemetry.Value.t
(** An attribute value, reusing opentelemetry's attribute value type. *)

(** The phase ("ph") of a TEF event, restricted to the subset we handle. *)
type phase =
  | X of { dur: float }
      (** complete/duration event: starts at [ts], lasts [dur] *)
  | Begin of { id: int }  (** async begin ("b"), matched to an [End] by [id] *)
  | End of { id: int }  (** async end ("e") *)
  | Instant  (** instant ("I"/"i"): a point in time *)
  | Counter  (** counter ("C"): metric values live in [args] *)
  | Meta_process_name of string  (** metadata "M" process_name *)
  | Meta_thread_name of string  (** metadata "M" thread_name *)
  | Meta_other  (** other metadata (sort indices, …): ignored *)

type t = {
  pid: int;
  tid: int;  (** thread id; [0] when absent *)
  ts: float;  (** timestamp, in microseconds; [0.] when absent *)
  name: string;
  phase: phase;
  args: (string * value) list;  (** decoded [args] object, if any *)
}

let value_of_json (j : Yojson.Safe.t) : value =
  match j with
  | `Int i -> `Int i
  | `Intlit s -> (try `Int (int_of_string s) with _ -> `String s)
  | `Float f -> `Float f
  | `Bool b -> `Bool b
  | `String s -> `String s
  | `Null -> `None
  | _ -> `None

let parse_obj (j : Yojson.Safe.t) : t option =
  match j with
  | `Assoc kvs ->
    let get k = List.assoc_opt k kvs in
    let str_field k =
      match get k with
      | Some (`String s) -> Some s
      | _ -> None
    in
    let int_field k =
      match get k with
      | Some (`Int i) -> Some i
      | Some (`Intlit s) -> int_of_string_opt s
      | Some (`Float f) -> Some (int_of_float f)
      | _ -> None
    in
    let float_field k =
      match get k with
      | Some (`Float f) -> Some f
      | Some (`Int i) -> Some (float_of_int i)
      | Some (`Intlit s) -> float_of_string_opt s
      | _ -> None
    in
    let name = Option.value ~default:"" (str_field "name") in
    let args =
      match get "args" with
      | Some (`Assoc a) -> List.map (fun (k, v) -> k, value_of_json v) a
      | _ -> []
    in
    let args_name () =
      match List.assoc_opt "name" args with
      | Some (`String s) -> s
      | _ -> ""
    in
    let phase =
      match str_field "ph" with
      | Some "X" ->
        Some (X { dur = Option.value ~default:0. (float_field "dur") })
      | Some "b" ->
        Some (Begin { id = Option.value ~default:0 (int_field "id") })
      | Some "e" -> Some (End { id = Option.value ~default:0 (int_field "id") })
      | Some ("I" | "i") -> Some Instant
      | Some "C" -> Some Counter
      | Some "M" ->
        (match name with
        | "process_name" -> Some (Meta_process_name (args_name ()))
        | "thread_name" -> Some (Meta_thread_name (args_name ()))
        | _ -> Some Meta_other)
      | _ -> None
      (* unknown phase: dropped *)
    in
    Option.map
      (fun phase ->
        {
          pid = Option.value ~default:0 (int_field "pid");
          tid = Option.value ~default:0 (int_field "tid");
          ts = Option.value ~default:0. (float_field "ts");
          name;
          phase;
          args;
        })
      phase
  | _ -> None

(** Parse a TEF JSON array (the default ocaml-trace output). *)
let parse_string (s : string) : t list =
  match Yojson.Safe.from_string s with
  | `List l -> List.filter_map parse_obj l
  | _ -> []
  | exception _ -> []

(** Parse newline-delimited TEF (one JSON object per line, "jsonl" mode). *)
let parse_jsonl (s : string) : t list =
  String.split_on_char '\n' s
  |> List.filter_map (fun line ->
         let line = String.trim line in
         if line = "" then
           None
         else (
           match Yojson.Safe.from_string line with
           | j -> parse_obj j
           | exception _ -> None
         ))
