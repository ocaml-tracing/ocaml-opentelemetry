(** Interface for a thread-safe, bounded queue.

    After the high watermark is reached, pushing items into the queue will
    instead discard them. *)

exception Closed
(** Raised when pushing into a closed queue *)

type 'a pop_result =
  [ `Empty
  | `Closed
  | `Item of 'a
  ]

module Common = struct
  type t = {
    closed: unit -> bool;
        (** Is the queue closed {b for writing}. Consumers should only use
            [try_pop] because a queue that's closed-for-writing might still
            contain straggler items that need to be consumed.

            This should be as fast and cheap as possible. *)
    num_discarded: unit -> int;  (** How many items were discarded? *)
    size: unit -> int;
        (** Snapshot of how many items are currently in the queue *)
    high_watermark: unit -> int;  (** Maximum size of the queue *)
  }

  let[@inline] num_discarded self = self.num_discarded ()

  let[@inline] closed (self : t) : bool = self.closed ()

  let[@inline] size (self : t) : int = self.size ()

  let[@inline] high_watermark self = self.high_watermark ()
end

(** Receiving side *)
module Recv = struct
  type 'a t = {
    on_non_empty: (unit -> unit) -> unit;
        (** [on_non_empty f] registers [f] to be called whenever the queue
            transitions from empty to non-empty. *)
    try_pop: unit -> 'a pop_result;  (** Try to pop an item right now. *)
    common: Common.t;
  }

  let[@inline] try_pop (self : _ t) : _ pop_result = self.try_pop ()

  let[@inline] on_non_empty (self : _ t) f = self.on_non_empty f

  let[@inline] closed (self : _ t) : bool = self.common.closed ()

  let[@inline] num_discarded self = self.common.num_discarded ()

  let[@inline] size self = self.common.size ()

  let[@inline] high_watermark self = self.common.high_watermark ()

  let map (type a b) (f : a -> b) (self : a t) : b t =
    {
      self with
      try_pop =
        (fun () ->
          match self.try_pop () with
          | (`Closed | `Empty) as r -> r
          | `Item x -> `Item (f x));
    }
end

(** Sending side *)
module Send = struct
  type 'a t = {
    push: 'a list -> unit;
        (** Push items. This might discard some of them.
            @raise Closed if the queue is closed. *)
    close: unit -> unit;
        (** Close the queue. Items currently in the queue will still be
            accessible to consumers until the queue is emptied out. Idempotent.
        *)
    common: Common.t;
  }

  let[@inline] push (self : _ t) x : unit = self.push x

  let[@inline] close (self : _ t) : unit = self.close ()

  let[@inline] closed (self : _ t) : bool = self.common.closed ()

  let[@inline] num_discarded self = self.common.num_discarded ()

  let[@inline] size self = self.common.size ()

  let[@inline] high_watermark self = self.common.high_watermark ()

  let map (type a b) (f : a list -> b list) (self : b t) : a t =
    {
      self with
      push =
        (fun xs ->
          match f xs with
          | [] -> ()
          | ys -> self.push ys);
    }

  (** Turn the writing end of the queue into an emitter.
      @param close_queue_on_close
        if true, closing the emitter will close the queue *)
  let to_emitter ~signal_name ~close_queue_on_close (self : 'a t) :
      'a Opentelemetry_emitter.Emitter.t =
    let closed () = closed self in
    let enabled () = not (closed ()) in
    let emit x = if x <> [] then push self x in
    let tick ~mtime:_ = () in

    (* the exporter will emit these, the queue is shared *)
    let self_metrics ~now:_ () = [] in

    (* NOTE: we cannot actually flush, only close. Emptying the queue is
     fundamentally asynchronous because it's done by consumers *)
    let flush_and_close () = if close_queue_on_close then close self in
    { signal_name; closed; enabled; emit; tick; flush_and_close; self_metrics }
end

type 'a t = {
  send: 'a Send.t;
  recv: 'a Recv.t;
}
(** A bounded queue, with multiple producers and potentially multiple consumers.

    All functions must be thread-safe except for [try_pop] which might not have
    to be depending on the context (e.g. a Lwt-specific queue implementation
    will consume only from the Lwt thread). *)

module Defaults = struct
  (** The default high watermark *)
  let high_watermark : int = 2048
end
