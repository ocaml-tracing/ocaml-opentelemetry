(** Logs.

    The logger is an object that can be used to emit logs.

    See
    {{:https://opentelemetry.io/docs/reference/specification/overview/#log-signal}
     the spec} *)

open Opentelemetry_emitter

type t = {
  emit: Log_record.t Emitter.t;
  clock: Clock.t;
}

(** Dummy logger, always disabled *)
let dummy : t = { emit = Emitter.dummy; clock = Clock.ptime_clock }

let[@inline] enabled (self : t) : bool = Emitter.enabled self.emit

let[@inline] emit1 (self : t) (l : Log_record.t) = Emitter.emit self.emit [ l ]

let of_exporter (exp : Exporter.t) : t =
  let emit =
    Emitter.make ~signal_name:"logs"
      ~emit:(fun logs -> exp.Exporter.export (Any_signal_l.Logs logs))
      ()
  in
  { emit; clock = Clock.Main.get () }
