open Opentelemetry

let pp_traceparent fmt (trace_id, parent_id) =
  let open Format in
  fprintf fmt "trace_id:%S parent_id:%S" (Trace_id.to_hex trace_id)
    (Span_id.to_hex parent_id)

let test_of_value str =
  let open Format in
  printf "@[<v 2>Trace_context.Traceparent.of_value %S:@ %a@]@." str
    (pp_print_result
       ~ok:(fun fmt (trace_id, parent_id) ->
         fprintf fmt "Ok %a" pp_traceparent (trace_id, parent_id))
       ~error:(fun fmt msg -> fprintf fmt "Error %S" msg))
    (Trace_context.Traceparent.of_value str)

let () = test_of_value "xx"

let () = test_of_value "00"

let () = test_of_value "00-xxxx"

let () = test_of_value "00-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

let () = test_of_value "00-0123456789abcdef0123456789abcdef"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-xxxx"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-xxxxxxxxxxxxxxxx"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-0123456789abcdef"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-0123456789abcdef-"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-0123456789abcdef-00"

let () = test_of_value "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

let () = test_of_value "03-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

let () = test_of_value "00-ohnonohex7b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

let () = test_of_value "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aazzzzzzb7-01"

let () = print_endline ""

let test_to_value trace_id parent_id =
  let open Format in
  printf "@[<v 2>Trace_context.Traceparent.to_value %a:@ %S@]@." pp_traceparent
    (trace_id, parent_id)
    (Trace_context.Traceparent.to_value ~trace_id ~parent_id ())

let () =
  test_to_value
    (Trace_id.of_hex "4bf92f3577b34da6a3ce929d0e0e4736")
    (Span_id.of_hex "00f067aa0ba902b7")

let () = print_endline ""

(* Trace_state tests *)

let test_trace_state_rt str =
  let open Format in
  let result = Trace_state.of_w3c_string str in
  match result with
  | Ok ts ->
    printf "of_w3c_string %S -> Ok %S (len=%d)@." str
      (Trace_state.to_w3c_string ts)
      (Trace_state.encoded_length ts)
  | Error e -> printf "of_w3c_string %S -> Error %S@." str e

let () = test_trace_state_rt ""

let () = test_trace_state_rt "congo=t61rcwkgmze"

let () = test_trace_state_rt "congo=t61rcwkgmze,rojo=00f067aa0ba902b7"

let () = test_trace_state_rt "  vendor=value  "

let () = test_trace_state_rt "bad key=value"

let () = test_trace_state_rt "key=val,=bad,other=fine"

let () = print_endline ""

let test_trace_state_set () =
  let ts = Trace_state.empty in
  let ts = Trace_state.set ts "vendor" "abc" in
  let ts = Trace_state.set ts "other" "xyz" in
  let ts = Trace_state.set ts "vendor" "new" in
  Format.printf "set/replace: %S@." (Trace_state.to_w3c_string ts);
  let ts = Trace_state.delete ts "other" in
  Format.printf "after delete: %S@." (Trace_state.to_w3c_string ts);
  Format.printf "get vendor: %S@."
    (Option.value ~default:"(none)" (Trace_state.get ts "vendor"))

let () = test_trace_state_set ()

let () = print_endline ""

let test_tracestate_header () =
  let module TS = Trace_context.Tracestate in
  Format.printf "Tracestate.name = %S@." TS.name;
  (match TS.of_w3c_string "a=b,c=d" with
  | Ok ts ->
    Format.printf "of_w3c_string round-trip: %S@." (TS.to_w3c_string ts)
  | Error e -> Format.printf "of_w3c_string error: %S@." e);
  match TS.of_w3c_string "" with
  | Ok ts -> Format.printf "of_w3c_string empty: %S@." (TS.to_w3c_string ts)
  | Error e -> Format.printf "of_w3c_string error: %S@." e

let () = test_tracestate_header ()
