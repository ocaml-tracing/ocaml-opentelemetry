(** W3C Trace State.

    A list of vendor-specific key/value pairs propagated across distributed
    tracing systems.

    @since NEXT_RELEASE

    https://www.w3.org/TR/trace-context/#tracestate-header *)

type t = (string * string) list

val empty : t

val is_valid_key : string -> bool
(** [is_valid_key k] is true if [k] is a valid W3C tracestate key. Keys must
    start with [a-z], followed by [a-z0-9_-*/], and be at most 256 chars. *)

val is_valid_value : string -> bool
(** [is_valid_value v] is true if [v] is a valid W3C tracestate value. Values
    must be printable ASCII (0x20–0x7E), excluding [,] and [=], with no
    leading/trailing space, and at most 256 chars. *)

val get : t -> string -> string option

val set : t -> string -> string -> t
(** [set ts key value] adds or replaces [key] in [ts], placing it at the front
    (most-recently-updated), per the W3C spec.
    @raise Invalid_argument
      if [key] or [value] fail their respective validators. *)

val delete : t -> string -> t

val encoded_length : t -> int
(** Length of the string produced by {!to_w3c_string}. *)

val to_w3c_string : t -> string
(** Encodes as a W3C tracestate header value ([k1=v1,k2=v2,...]). Returns [""]
    for an empty list. *)

val of_w3c_string : string -> (t, string) result
(** Parses a W3C tracestate header value. Malformed or invalid entries are
    silently skipped rather than returning an error. *)
