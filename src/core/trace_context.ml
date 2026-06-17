(** Implementation of the W3C Trace Context spec

    https://www.w3.org/TR/trace-context/ *)

(** The traceparent header
    https://www.w3.org/TR/trace-context/#traceparent-header *)
module Traceparent = struct
  let name = "traceparent"

  (** Parse the value of the traceparent header.

      The values are of the form:

      {[
        { version } - { trace_id } - { parent_id } - { flags }
      ]}

      For example:

      {[
        00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
      ]}

      [{flags}] are currently ignored. *)
  let of_value str : (Trace_id.t * Span_id.t, string) result =
    match Span_ctx.of_w3c_trace_context (Bytes.unsafe_of_string str) with
    | Ok sp -> Ok (Span_ctx.trace_id sp, Span_ctx.parent_id sp)
    | Error _ as e -> e

  let to_value ?(sampled : bool option) ~(trace_id : Trace_id.t)
      ~(parent_id : Span_id.t) () : string =
    let span_ctx = Span_ctx.make ?sampled ~trace_id ~parent_id () in
    Bytes.unsafe_to_string @@ Span_ctx.to_w3c_trace_context span_ctx
end

(** The tracestate header https://www.w3.org/TR/trace-context/#tracestate-header
*)
module Tracestate = struct
  let name = "tracestate"

  let of_w3c_string (s : string) : (Trace_state.t, string) result =
    Trace_state.of_w3c_string s

  let to_w3c_string (ts : Trace_state.t) : string = Trace_state.to_w3c_string ts
end
