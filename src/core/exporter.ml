(** Exporter.

    This is the pluggable component that actually sends signals to a OTEL
    collector, or prints them, or saves them somewhere.

    This is part of the SDK, not just the API, so most real implementations live
    in their own library. *)

open Common_
open Opentelemetry_emitter

type t = {
  active: unit -> Aswitch.t;
      (** Is the exporer currently active? After shutdown this is turned off. *)
  clock: Clock.t;
  emit_spans: Proto.Trace.span Emitter.t;
  emit_metrics: Proto.Metrics.metric Emitter.t;
  emit_logs: Proto.Logs.log_record Emitter.t;
  on_tick: (unit -> unit) -> unit;
  tick: unit -> unit;
      (** Call all the callbacks registered with [on_tick]. Should be triggered
          regularly for background processing, timeout checks, etc. *)
  shutdown: unit -> unit;
      (** [shutdown ()] is called when the exporter is shut down, and is
          responsible for sending remaining batches, flushing sockets, etc. To
          know when shutdown is complete, register callbacks on [active].
          @since 0.12 *)
  self_metrics: unit -> Metrics.t list;  (** metrics about the exporter itself *)
}
(** Main exporter interface. *)

(** Dummy exporter, does nothing *)
let dummy () : t =
  let ticker = Cb_set.create () in
  let active, trigger = Aswitch.create () in
  {
    active = (fun () -> active);
    clock = Clock.ptime_clock;
    emit_spans = Emitter.dummy;
    emit_metrics = Emitter.dummy;
    emit_logs = Emitter.dummy;
    on_tick = Cb_set.register ticker;
    tick = (fun () -> Cb_set.trigger ticker);
    shutdown = (fun () -> Aswitch.turn_off trigger);
    self_metrics = (fun () -> []);
  }

let[@inline] send_trace (self : t) (l : Proto.Trace.span list) =
  Emitter.emit self.emit_spans l

let[@inline] send_metrics (self : t) (l : Proto.Metrics.metric list) =
  Emitter.emit self.emit_metrics l

let[@inline] send_logs (self : t) (l : Proto.Logs.log_record list) =
  Emitter.emit self.emit_logs l

let[@inline] on_tick (self : t) f = self.on_tick f

(** Do background work. Call this regularly if the collector doesn't already
    have a ticker thread or internal timer. *)
let tick ~mtime (self : t) =
  (* make sure emitters get the chance to check timeouts, flush, etc. *)
  Emitter.tick ~mtime self.emit_spans;
  Emitter.tick ~mtime self.emit_metrics;
  Emitter.tick ~mtime self.emit_logs;

  (* call the callbacks *)
  self.tick ();
  ()

let[@inline] active self : Aswitch.t = self.active ()

(** [on_stop e f] calls [f()] when [e] stops, or now if it's already stopped *)
let on_stop self f = Aswitch.on_turn_off (self.active ()) f

let[@inline] shutdown (self : t) : unit = self.shutdown ()

let (cleanup [@deprecated "use shutdown instead"]) = shutdown

let self_metrics (self : t) : _ list =
  let now = Clock.now self.clock in
  List.flatten
    [
      self.self_metrics ();
      self.emit_spans.self_metrics ~now ();
      self.emit_logs.self_metrics ~now ();
      self.emit_metrics.self_metrics ~now ();
    ]
