open Common_

(* see: https://opentelemetry.io/docs/specs/otel/trace/api/#spancontext *)

module Flags = Trace_flags

type t = {
  trace_id: Trace_id.t;
  parent_id: Span_id.t;
  trace_flags: Trace_flags.t;
  trace_state: string;
}

let dummy =
  {
    trace_id = Trace_id.dummy;
    parent_id = Span_id.dummy;
    trace_flags = Trace_flags.none;
    trace_state = "";
  }

let make ?(trace_state = "") ~trace_flags ~trace_id ~parent_id () : t =
  { trace_id; parent_id; trace_flags; trace_state }

let[@inline] is_valid self =
  Trace_id.is_valid self.trace_id && Span_id.is_valid self.parent_id

let[@inline] trace_flags self = self.trace_flags

let[@inline] sampled self = Trace_flags.is_sampled self.trace_flags

let[@inline] trace_id self = self.trace_id

let[@inline] parent_id self = self.parent_id

let[@inline] trace_state self = self.trace_state

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
  let flags = Trace_flags.to_int self.trace_flags in
  Bytes.set bs 53 (Util_bytes_.hex_upper_nibble flags);
  Bytes.set bs 54 (Util_bytes_.hex_lower_nibble flags);
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
    let trace_flags =
      match int_of_string_opt ("0x" ^ Bytes.sub_string bs 53 2) with
      | Some flags -> Trace_flags.of_int flags (* unknown flags are dropped *)
      | None -> Trace_flags.none
    in
    Ok (make ~trace_flags ~trace_id ~parent_id ())
  with Invalid_argument msg -> Error msg

let of_w3c_trace_context_exn bs =
  match of_w3c_trace_context bs with
  | Ok t -> t
  | Error msg -> invalid_arg @@ spf "invalid w3c trace context: %s" msg

let k_ambient : t Hmap.key = Hmap.Key.create ()
