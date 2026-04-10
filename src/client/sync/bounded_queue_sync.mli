(** Bounded queue based on simple synchronization primitives.

    This is not the fastest queue but it should be versatile. *)

val create :
  ?measure:('a -> int) -> high_watermark:int -> unit -> 'a Bounded_queue.t
(** [create ~high_watermark ()] creates a new bounded queue based on
    {!Sync_queue}.
    @param measure
      maps each item to its signal count (e.g. number of spans in a batch). Used
      to report accurate signal counts when items are dropped. Default:
      [fun _ -> 1]. *)
