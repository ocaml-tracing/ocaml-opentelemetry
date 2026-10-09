(** W3C trace flags.

    {{:https://www.w3.org/TR/trace-context-2/#trace-flags}
     https://www.w3.org/TR/trace-context-2/#trace-flags}

    Only the [sampled] (0x01) and [random-trace-id] (0x02) flags are defined;
    other bits are reserved and "Vendors MUST set those to zero", so they are
    always cleared.
    @since NEXT_RELEASE *)

type t = private int

val none : t
(** No flag set *)

val sampled : t
(** Only the [sampled] flag *)

val default : t
(** [sampled] and [random] (0x03). Default for {!Span.make}, and for spans
    without flags *)

val make : sampled:bool -> random:bool -> t

val of_int : int -> t
(** Keep only the known flags *)

val to_int : t -> int

val of_int32 : int32 -> t
(** Keep only the known flags, e.g. from the OTLP [flags] field *)

val to_int32 : t -> int32

val is_sampled : t -> bool
(** "When set, the least significant bit (right-most), denotes that the caller
    may have recorded trace data." *)

val is_random : t -> bool
(** "When set, at least the right-most 7 bytes of the trace-id MUST be selected
    randomly (or pseudo-randomly)". It must be propagated unchanged for a given
    trace ID. *)

val with_sampled : bool -> t -> t

val with_random : bool -> t -> t

val pp : Format.formatter -> t -> unit
