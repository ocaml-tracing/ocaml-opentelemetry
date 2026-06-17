(** Span context. This bundles up a trace ID and parent ID.

    {{:https://opentelemetry.io/docs/specs/otel/trace/api/#spancontext}
     https://opentelemetry.io/docs/specs/otel/trace/api/#spancontext}
    @since 0.7 *)

type t

val make :
  ?remote:bool ->
  ?sampled:bool ->
  ?trace_state:Trace_state.t ->
  trace_id:Trace_id.t ->
  parent_id:Span_id.t ->
  unit ->
  t

val dummy : t
(** Invalid span context, to be used as a placeholder *)

val is_remote : t -> bool
(** Does this come from a remote parent? *)

val is_valid : t -> bool
(** Are the span ID and trace ID valid (ie non-zero)? *)

val trace_id : t -> Trace_id.t

val parent_id : t -> Span_id.t

val sampled : t -> bool

val trace_state : t -> Trace_state.t

val to_w3c_trace_context : t -> bytes

val of_w3c_trace_context : bytes -> (t, string) result

val of_w3c_trace_context_exn : bytes -> t
(** @raise Invalid_argument if parsing failed *)

val k_ambient : t Hmap.key
(** Hmap key to carry around a {!Span_ctx.t}, e.g. to remember what the current
    parent span is.
    @since 0.8 *)
