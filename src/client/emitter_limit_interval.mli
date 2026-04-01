(** Limit frequency at which the emitter emits.

    This puts a hard floor on the interval between two consecutive successful
    [emit]. Attempts to emit too early are simply discarded.

    The use case for this is metrics: it's possible, for a gauge, to just drop
    some entries if we've been emitting them too frequently.

    {b NOTE}: it's better to do [limit_interval ~min_interval (add_batching e)]
    than [add_batching (limit_interval ~min_interval e)], because in the later
    case we might be dismissing a whole large batch at ine

    @since 0.90 *)

open Common_.OTEL

val add_interval_limiter : Interval_limiter.t -> 'a Emitter.t -> 'a Emitter.t
(** [add_interval_limiter il e] is a new emitter [e'] that can only emit signals
    less frequently than [Interval_limiter.min_interval il].

    Trying to emit too early will simply drop the signal. *)

val limit_interval : min_interval:Mtime.span -> 'a Emitter.t -> 'a Emitter.t
(** [limit_interval ~min_interval e] is
    [add_interval_limiter (Interval_limiter.create ~min_interval ()) e] *)
