(** Span context. This bundles up a trace ID and parent ID.

    {{:https://opentelemetry.io/docs/specs/otel/trace/api/#spancontext}
     https://opentelemetry.io/docs/specs/otel/trace/api/#spancontext}
    @since 0.7 *)

type t

module Flags = Trace_flags
(** @since NEXT_RELEASE *)

val make :
  ?trace_state:string ->
  trace_flags:Trace_flags.t ->
  trace_id:Trace_id.t ->
  parent_id:Span_id.t ->
  unit ->
  t
(** @param trace_flags
      W3C trace flags. They must reflect the trace's actual sampling decision
      and trace ID randomness, so there is no default. Since NEXT_RELEASE
    @param trace_state W3C [tracestate] value, since NEXT_RELEASE *)

val dummy : t
(** Invalid span context, to be used as a placeholder *)

val is_valid : t -> bool
(** Are the span ID and trace ID valid (ie non-zero)? *)

val trace_id : t -> Trace_id.t

val parent_id : t -> Span_id.t

val trace_flags : t -> Trace_flags.t
(** W3C trace flags.
    @since NEXT_RELEASE *)

val sampled : t -> bool
(** [Trace_flags.is_sampled (trace_flags self)] *)

val trace_state : t -> string
(** W3C [tracestate] value, [""] if absent.
    @since NEXT_RELEASE *)

val to_w3c_trace_context : t -> bytes

val of_w3c_trace_context : bytes -> (t, string) result

val of_w3c_trace_context_exn : bytes -> t
(** @raise Invalid_argument if parsing failed *)

val k_ambient : t Hmap.key
(** Hmap key to carry around a {!Span_ctx.t}, e.g. to remember what the current
    parent span is.
    @since 0.8 *)
