(** [opentelemetry.trace] implements a {!Trace_core.Collector} for
    {{:https://v3.ocaml.org/p/trace} ocaml-trace}.

    After installing this collector with {!setup}, you can consume libraries
    that use [ocaml-trace], and they will automatically emit OpenTelemetry spans
    and logs.

    Ambient_context is used to track the current ambient span.

    We use [Trace_core.extension_event] to add more features on top of the
    common tracing interface. For example to set the "span kind":

    {[
      let@ span = Trace_core.with_span ~__FILE__ ~__LINE__ "my-span" in
      Opentelemetry_trace.set_span_kind span Span_kind_client
      (* ... *)
    ]} *)

module OTEL := Opentelemetry_core
module Otrace := Trace_core

(** The extension events for {!Trace_core}. *)
module Extensions : sig
  type Otrace.span +=
    | Span_otel of OTEL.Span.t  (** The type of span used for OTEL *)

  type Otrace.extension_event +=
    | Ev_link_span of Otrace.span * OTEL.Span_ctx.t
          (** Link the given span to the given context. The context isn't the
              parent, but the link can be used to correlate both spans. *)
    | Ev_record_exn of {
        sp: Otrace.span;
        exn: exn;
        bt: Printexc.raw_backtrace;
      }
          (** Record exception and potentially turn span to an error *)
    | Ev_set_span_kind of Otrace.span * OTEL.Span_kind.t
    | Ev_set_span_status of Otrace.span * OTEL.Span_status.t

  type Otrace.metric +=
    | Metric_hist of OTEL.Metrics.histogram_data_point
    | Metric_sum_int of int
    | Metric_sum_float of float
end

val setup : unit -> unit
(** Install the OTEL backend as a Trace collector *)

val setup_with_otel_exporter : OTEL.Exporter.t -> unit
(** Same as {!setup}, but using the given exporter *)

val setup_with_otel_backend : OTEL.Exporter.t -> unit
[@@deprecated "use setup_with_otel_exporter"]

val collector_of_exporter : OTEL.Exporter.t -> Trace_core.collector

val collector : unit -> Trace_core.collector
[@@deprecated "use collector_of_exporter, avoid global state"]
(** Make a Trace collector that uses the main OTEL backend to send spans and
    logs *)

val ambient_span_provider : Trace_core.Ambient_span_provider.t
(** Uses {!Ambient_context} to provide contextual spans in {!Trace_core}.*)

val link_spans : Otrace.span -> Otrace.span -> unit
(** [link_spans sp1 sp2] modifies [sp1] by adding a span link to [sp2].
    @since 0.11 *)

val link_span_to_otel_ctx : Otrace.span -> OTEL.Span_ctx.t -> unit
(** [link_spans sp1 sp_ctx2] modifies [sp1] by adding a span link to [sp_ctx2].
    It must be the case that [sp1] is a currently active span.
    @since NEXT_RELEASE *)

val set_span_kind : Otrace.span -> OTEL.Span.kind -> unit
(** [set_span_kind sp k] sets the span's kind. *)

val set_span_status : Otrace.span -> OTEL.Span_status.t -> unit
(** @since NEXT_RELEASE *)

val record_exception : Otrace.span -> exn -> Printexc.raw_backtrace -> unit
(** Record exception in the current span. *)

val with_ambient_span : Otrace.span -> (unit -> 'a) -> 'a
(** [with_ambient_span sp f] calls [f()] in an ambient context where [sp] is the
    current span. *)

val with_ambient_span_ctx : OTEL.Span_ctx.t -> (unit -> 'a) -> 'a
(** [with_ambient_span_ctx spc f] calls [f()] in a scope where [spc] is the
    ambient span-context *)

module Well_known : sig end
[@@deprecated
  "use the regular functions such as `link_spans` or `set_span_kind` for this"]
