(** [opentelemetry.trace] implements a {!Trace_core.Collector} for
    {{:https://v3.ocaml.org/p/trace} ocaml-trace}.

    After installing this collector with {!setup}, you can consume libraries
    that use [ocaml-trace], and they will automatically emit OpenTelemetry spans
    and logs.

    [Ambient_context] is used to propagate the current span to child spans.

    [Trace_core.extension_event] is used to expose OTEL-specific features on top
    of the common tracing interface, e.g. to set the span kind:

    {[
      let@ span = Trace_core.with_span ~__FILE__ ~__LINE__ "my-span" in
      Opentelemetry_trace.set_span_kind span Span_kind_client
      (* ... *)
    ]} *)

module Otel := Opentelemetry
module Otrace := Trace_core

type Otrace.extension_event +=
  | Ev_link_span of Otrace.span * Otrace.span
        (** Link the two spans together. Both must be currently active spans. *)
  | Ev_set_span_kind of Otrace.span * Otel.Span_kind.t
  | Ev_record_exn of Otrace.span * exn * Printexc.raw_backtrace
        (** Record exception and potentially turn span to an error *)

val on_internal_error : (string -> unit) ref
(** Callback to print errors in the library itself (ie bugs) *)

val setup : unit -> unit
(** Install the OTEL backend as a Trace collector *)

val setup_with_otel_backend : Opentelemetry.Collector.backend -> unit
(** Same as {!setup}, but also install the given backend as OTEL backend *)

val collector : unit -> Trace_core.collector
(** Make a Trace collector that uses the OTEL backend to send spans and logs *)

val link_spans : Otrace.span -> Otrace.span -> unit
(** [link_spans sp1 sp2] modifies [sp1] by adding a span link to [sp2].
    @since 0.11 *)

val set_span_kind : Otrace.span -> Otel.Span_kind.t -> unit
(** [set_span_kind sp k] sets the span's kind.
    @since 0.11 *)

val record_exception : Otrace.span -> exn -> Printexc.raw_backtrace -> unit
(** Record exception in the current span.
    @since 0.11 *)

val with_ambient_span : Otrace.span -> (unit -> 'a) -> 'a
(** [with_ambient_span sp f] calls [f()] in an ambient context where [sp] is the
    current span. *)

module Well_known : sig end
[@@deprecated
  "use the regular functions such as `link_spans` or `set_span_kind` for this"]
(** Static references for well-known identifiers *)
