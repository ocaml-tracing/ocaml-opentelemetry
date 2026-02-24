(** Exporter.

    This is the pluggable component that actually sends signals to a OTEL
    collector, or prints them, or saves them somewhere.

    This is part of the SDK, not just the API, so most real implementations live
    in their own library. *)

type t = {
  export: Any_signal_l.t -> unit;
      (** Export a batch of signals. Called by the provider when signals are
          ready to be sent. *)
  active: unit -> Aswitch.t;
      (** Lifecycle switch: turns off when the exporter has fully shut down
          (i.e. the consumer queue is drained). *)
  shutdown: unit -> unit;
      (** [shutdown ()] initiates shutdown: flushes remaining batches, closes
          the queue, etc. Watch [active] to know when it's complete.
          @since 0.12 *)
  self_metrics: unit -> Metrics.t list;  (** metrics about the exporter itself *)
}
(** Main exporter interface. *)

(** Dummy exporter, does nothing *)
let dummy () : t =
  {
    export = ignore;
    active = (fun () -> Aswitch.dummy);
    shutdown = ignore;
    self_metrics = (fun () -> []);
  }

let[@inline] active (self : t) : Aswitch.t = self.active ()

let[@inline] shutdown (self : t) : unit = self.shutdown ()

let (cleanup [@deprecated "use shutdown instead"]) = shutdown

let[@inline] self_metrics (self : t) : _ list = self.self_metrics ()
