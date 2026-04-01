(** Spans.

    A Span is the workhorse of traces, it indicates an operation that took place
    over a given span of time (indicated by start_time and end_time) as part of
    a hierarchical trace. All spans in a given trace are bound by the use of the
    same {!Trace_id.t}. *)

open Common_
open Proto.Trace

type t = span

type id = Span_id.t

type kind = Span_kind.t =
  | Span_kind_unspecified
  | Span_kind_internal
  | Span_kind_server
  | Span_kind_client
  | Span_kind_producer
  | Span_kind_consumer

type key_value = Key_value.t

val pp : Format.formatter -> t -> unit

val make :
  ?kind:kind ->
  ?trace_state:string ->
  ?attrs:key_value list ->
  ?events:Event.t list ->
  ?status:status ->
  trace_id:Trace_id.t ->
  id:Span_id.t ->
  ?parent:id ->
  ?links:Span_link.t list ->
  start_time:Timestamp_ns.t ->
  end_time:Timestamp_ns.t ->
  string ->
  t
(** [make ~trace_id ~id name] creates a new span
    @param trace_id the trace this belongs to
    @param parent parent span, if any
    @param links
      list of links to other spans, each with their trace state (see
      {{:https://www.w3.org/TR/trace-context/#tracestate-header} w3.org}) *)

val id : t -> Span_id.t

val trace_id : t -> Trace_id.t

val is_not_dummy : t -> bool

val dummy : t
(** Dummy span, will not record anything *)

val create_new :
  ?kind:kind ->
  ?id:Span_id.t ->
  ?trace_state:string ->
  ?attrs:key_value list ->
  ?events:Event.t list ->
  ?status:status ->
  trace_id:Trace_id.t ->
  ?parent:id ->
  ?links:Span_link.t list ->
  start_time:Timestamp_ns.t ->
  end_time:Timestamp_ns.t ->
  string ->
  t

val attrs : t -> Key_value.t list

val events : t -> Event.t list

val links : t -> Span_link.t list

val status : t -> Span_status.t option

val kind : t -> Span_kind.t option

val to_span_link : t -> Span_link.t
(** Turn the scope into a span link *)

val to_span_ctx : t -> Span_ctx.t
(** Turn the scope into a span context *)

val add_event : t -> Event.t -> unit

val add_event' : t -> (unit -> Event.t) -> unit
(** Add an event to the scope. It will be aggregated into the span.

    Note that this takes a function that produces an event, and will only call
    it if there is an instrumentation backend. *)

val record_exception : t -> exn -> Printexc.raw_backtrace -> unit
(** Record an exception occurring inside the span. This creates a span event
    {b and} also sets the span status to error. *)

val add_links : t -> Span_link.t list -> unit

val add_links' : t -> (unit -> Span_link.t list) -> unit
(** Add links to the scope. It will be aggregated into the span.

    Note that this takes a function that produces links, and will only call it
    if there is an instrumentation backend. *)

val add_attrs : t -> Key_value.t list -> unit

val add_attrs' : t -> (unit -> Key_value.t list) -> unit

val set_status : t -> Span_status.t -> unit
(** set the span status.

    Note that this function will be called only if there is an instrumentation
    backend. *)

val set_kind : t -> Span_kind.t -> unit
(** Set the span's kind.
    @since 0.11 *)

val default_kind : Span_kind.t ref
(** Default span kind in {!make} and {!create_new}.

    This will be used in all spans that do not specify [~kind] explicitly; it is
    set to "internal", following directions from the [.proto] file. It can be
    convenient to set "client" or "server" uniformly in here. *)

val k_ambient : t Context.key
(** Context key to carry around a {!Span.t} in ambient context.
    @since 0.90 *)
