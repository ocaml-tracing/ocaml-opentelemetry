(** Export GC metrics periodically. *)

val get_metrics : unit -> Metrics.t list
(** Get a snapshot of GC statistics as metrics. *)

val setup : ?min_interval_s:int -> ?meter:Meter.t -> unit -> unit
(** Register a tick callback that emits GC statistics periodically.
    @param min_interval_s emit at most every N seconds (default 20)
    @param meter where to emit metrics (default [Meter.default]) *)

val basic_setup : unit -> unit
(** [setup ()] — uses all defaults. *)
