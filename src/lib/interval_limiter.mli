(** Interval limiter. This is a form of rate limiting where an event cannot be
    followed by another event until a given interval of time has passed. *)

type t

val create : min_interval:Mtime.span -> unit -> t

val create_atomic : min_interval:Mtime.span Atomic.t -> unit -> t
(** Like {!create}, but the interval is read from the given atomic at each
    attempt, so it can be changed later by whoever holds the atomic.
    @since NEXT_RELEASE *)

val min_interval : t -> Mtime.span
(** Current minimum interval *)

val set_min_interval : t -> Mtime.span -> unit
(** Change the minimum interval. Takes effect on the next attempt.
    @since NEXT_RELEASE *)

val make_attempt : t -> bool
(** [make_attempt lim] returns [true] if the last successful attempt was more
    than [min_interval] ago, as measured by mtime. If so, this counts as the new
    latest attempt; otherwise [false] is returned and the state is not updated.
*)
