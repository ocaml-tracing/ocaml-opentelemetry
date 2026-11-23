(** Unique ID of a span. *)

type t

val create : unit -> t

val dummy : t

val pp : Format.formatter -> t -> unit

val is_valid : t -> bool

val to_bytes : t -> bytes

val of_bytes : bytes -> t
(** Takes 8 bytes and turns them into a Span ID. If all the bytes are 0 then the
    ID is invalid (but can still be constructed)
    @raise Invalid_argument if bytes are not of length 8 *)

val to_hex : t -> string

val to_hex_into : t -> bytes -> int -> unit

val of_hex : string -> t

val of_hex_substring : string -> int -> t

val set_create_function : (unit -> t) -> unit
(** [set_create_function f] replaces the default implementation of [create] with
    [f].
    @since NEXT_RELEASE *)

val default_create_function : unit -> t
(** The implementation behind {!create}
    @since NEXT_RELEASE *)
