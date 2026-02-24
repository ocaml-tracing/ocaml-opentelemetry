(** Traces.

    The tracer is an object that can be used to emit spans that form a trace.

    See
    {{:https://opentelemetry.io/docs/reference/specification/overview/#tracing-signal}
     the spec} *)

open Opentelemetry_emitter

type span = Span.t

type t = {
  emit: Span.t Emitter.t;
  clock: Clock.t;
}
(** A tracer.

    https://opentelemetry.io/docs/specs/otel/trace/api/#tracer *)

(** Dummy tracer, always disabled *)
let dummy : t = { emit = Emitter.dummy; clock = Clock.ptime_clock }

let[@inline] enabled (self : t) = Emitter.enabled self.emit

let of_exporter (exp : Exporter.t) : t =
  let emit =
    Emitter.make ~signal_name:"spans"
      ~emit:(fun spans -> exp.Exporter.export (Any_signal_l.Spans spans))
      ()
  in
  { emit; clock = Clock.Main.get () }
