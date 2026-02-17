open Common_

(* see: https://opentelemetry.io/docs/specs/otel/trace/api/#spancontext *)

(* TODO: trace state *)

external int_of_bool : bool -> int = "%identity"

module Flags = struct
  let sampled = 1

  let remote = 2
end

type t = {
  trace_id: Trace_id.t;
  parent_id: Span_id.t;
  flags: int;
}

let dummy = { trace_id = Trace_id.dummy; parent_id = Span_id.dummy; flags = 0 }

let make ?(remote = false) ?(sampled = false) ~trace_id ~parent_id () : t =
  let flags =
    0
    lor (int_of_bool remote lsl Flags.remote)
    lor (int_of_bool sampled lsl Flags.sampled)
  in
  { trace_id; parent_id; flags }

let[@inline] is_valid self =
  Trace_id.is_valid self.trace_id && Span_id.is_valid self.parent_id

let[@inline] sampled self = self.flags land (1 lsl Flags.sampled) != 0

let[@inline] is_remote self = self.flags land (1 lsl Flags.remote) != 0

let[@inline] trace_id self = self.trace_id

let[@inline] parent_id self = self.parent_id

let to_w3c_trace_context (self : t) : bytes =
  let bs = Bytes.create 55 in
  Bytes.set bs 0 '0';
  Bytes.set bs 1 '0';
  Bytes.set bs 2 '-';
  Trace_id.to_hex_into self.trace_id bs 3;
  (* +32 *)
  Bytes.set bs (3 + 32) '-';
  Span_id.to_hex_into self.parent_id bs 36;
  (* +16 *)
  Bytes.set bs 52 '-';
  Bytes.set bs 53 '0';
  Bytes.set bs 54
    (if sampled self then
       '1'
     else
       '0');
  bs

let of_w3c_trace_context bs : _ result =
  try
    if Bytes.length bs <> 55 then invalid_arg "trace context must be 55 bytes";
    (match int_of_string_opt (Bytes.sub_string bs 0 2) with
    | Some 0 -> ()
    | Some n -> invalid_arg @@ spf "version is %d, expected 0" n
    | None -> invalid_arg "expected 2-digit version");
    if Bytes.get bs 2 <> '-' then invalid_arg "expected '-' before trace_id";
    let trace_id =
      try Trace_id.of_hex_substring (Bytes.unsafe_to_string bs) 3
      with Invalid_argument msg -> invalid_arg (spf "in trace id: %s" msg)
    in
    if Bytes.get bs (3 + 32) <> '-' then
      invalid_arg "expected '-' before parent_id";
    let parent_id =
      try Span_id.of_hex_substring (Bytes.unsafe_to_string bs) 36
      with Invalid_argument msg -> invalid_arg (spf "in span id: %s" msg)
    in
    if Bytes.get bs 52 <> '-' then invalid_arg "expected '-' after parent_id";
    let sampled =
      match int_of_string_opt ("0x" ^ Bytes.sub_string bs 53 2) with
      | Some flags -> flags land 1 = 1
      | None -> false
    in

    (* ignore other flags *)
    Ok (make ~remote:true ~sampled ~trace_id ~parent_id ())
  with Invalid_argument msg -> Error msg

let of_w3c_trace_context_exn bs =
  match of_w3c_trace_context bs with
  | Ok t -> t
  | Error msg -> invalid_arg @@ spf "invalid w3c trace context: %s" msg

let k_ambient : t Hmap.key = Hmap.Key.create ()
