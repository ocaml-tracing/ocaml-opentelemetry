module BQ = Bounded_queue

type push_res =
  | Closed
  | Pushed of { num_discarded: int }

(* a variant of {!Sync_queue} with more bespoke pushing behavior *)
module Q : sig
  type 'a t

  val create : unit -> 'a t

  val close : _ t -> unit

  val size : _ t -> int

  val closed : _ t -> bool

  val try_pop : 'a t -> 'a BQ.pop_result

  val push_while_not_full : high_watermark:int -> 'a t -> 'a list -> push_res
  (** [push_while_not_full q ~high_watermark xs] tries to push each item of [x]
      into [q].

      An item is not pushed if the queue is "full" (size >= high_watermark).

      This returns a pair [num_discarded, old_size] where [num_discarded] is the
      number of items that could not be pushed, and [old_size] is the size
      before anything was pushed. *)
end = struct
  module UM = Util_mutex

  type 'a t = {
    mutex: Mutex.t;
    q: 'a Queue.t;
    mutable closed: bool;
  }

  let create () : _ t =
    { mutex = Mutex.create (); q = Queue.create (); closed = false }

  (* NOTE: the race condition here is benign, assuming no tearing of
    a value of type [bool] which OCaml's memory model should guarantee. *)
  let[@inline] closed self = self.closed

  let[@inline] size self = UM.protect self.mutex (fun () -> Queue.length self.q)

  let close (self : _ t) =
    UM.protect self.mutex @@ fun () ->
    if not self.closed then self.closed <- true

  let try_pop (self : 'a t) : 'a BQ.pop_result =
    UM.protect self.mutex @@ fun () ->
    (* first, try to pop the queue. We want to drain it even if it's closed. *)
    try `Item (Queue.pop self.q)
    with Queue.Empty ->
      if self.closed then
        `Closed
      else
        `Empty

  let push_while_not_full ~high_watermark (self : 'a t) (xs : 'a list) :
      push_res =
    UM.protect self.mutex @@ fun () ->
    if self.closed then
      Closed
    else (
      let to_push = ref xs in

      let continue = ref true in
      while !continue && Queue.length self.q < high_watermark do
        match !to_push with
        | [] -> continue := false
        | x :: tl_xs ->
          to_push := tl_xs;
          Queue.push x self.q
      done;

      let num_discarded = List.length !to_push in
      (* Printf.eprintf "bq: pushed %d items (discarded: %d)\n%!" (List.length xs - num_discarded) num_discarded; *)

      Pushed { num_discarded }
    )
end

type 'a state = {
  n_discarded: int Atomic.t;
  high_watermark: int;
  q: 'a Q.t;
  on_non_empty: Cb_set.t;
}

let push (self : _ state) x =
  if x <> [] then (
    match
      Q.push_while_not_full self.q ~high_watermark:self.high_watermark x
    with
    | Closed ->
      ignore (Atomic.fetch_and_add self.n_discarded (List.length x) : int)
    | Pushed { num_discarded } ->
      if num_discarded > 0 then
        ignore (Atomic.fetch_and_add self.n_discarded num_discarded : int);

      (* wake up potentially asleep consumers *)
      Cb_set.trigger self.on_non_empty
  )

let[@inline] try_pop (self : _ state) : _ BQ.pop_result = Q.try_pop self.q

let to_bounded_queue (self : 'a state) : 'a BQ.t =
  let closed () = Q.closed self.q in
  let num_discarded () = Atomic.get self.n_discarded in
  let push x = push self x in
  let on_non_empty = Cb_set.register self.on_non_empty in
  let try_pop () = try_pop self in
  let size () = Q.size self.q in
  let high_watermark () = self.high_watermark in
  let close () =
    Q.close self.q;
    (* waiters will want to know *)
    Cb_set.trigger self.on_non_empty
  in
  let common = { BQ.Common.closed; num_discarded; size; high_watermark } in
  {
    BQ.send = { push; close; common };
    recv = { try_pop; on_non_empty; common };
  }

let create ~high_watermark () : _ BQ.t =
  let st =
    {
      high_watermark;
      q = Q.create ();
      n_discarded = Atomic.make 0;
      on_non_empty = Cb_set.create ();
    }
  in
  to_bounded_queue st
