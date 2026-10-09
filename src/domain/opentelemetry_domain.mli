val cpu_relax : unit -> unit

val relax_loop : int -> unit
(** Call {!cpu_relax} n times *)

val is_main_domain : unit -> bool

module DLS : sig
  type 'a key

  val new_key : ?split_from_parent:('a -> 'a) -> (unit -> 'a) -> 'a key

  val get : 'a key -> 'a

  val set : 'a key -> 'a -> unit
end
