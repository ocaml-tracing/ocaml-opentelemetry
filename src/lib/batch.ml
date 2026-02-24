open Opentelemetry_atomic

type 'a state = {
  start: Mtime.t;
  size: int;
  q: 'a list;  (** The queue is a FIFO represented as a list in reverse order *)
}

type 'a t = {
  st: 'a state Atomic.t;
  batch: int;  (** Minimum size to batch before popping *)
  high_watermark: int;  (** Size above which we start dropping signals *)
  timeout: Mtime.span option;
  n_dropped: int Atomic.t;
}

let max_batch_size = 100_000

let default_high_watermark batch_size =
  max 10 (min (batch_size * 10) max_batch_size)

(** passed to ignore timeout *)
let mtime_dummy_ = Mtime.min_stamp

let _empty_state : _ state = { q = []; size = 0; start = mtime_dummy_ }

let[@inline] cur_size (self : _ t) : int = (Atomic.get self.st).size

let make ?(batch = 100) ?high_watermark ?mtime ?timeout () : _ t =
  let batch = min batch max_batch_size in
  let high_watermark =
    match high_watermark with
    | Some x -> max x batch (* high watermark must be >= batch *)
    | None -> default_high_watermark batch
  in
  assert (high_watermark >= batch);

  let start =
    match mtime with
    | Some x -> x
    | None -> mtime_dummy_
  in
  assert (batch > 0);
  {
    st = Atomic.make @@ { size = 0; q = []; start };
    batch;
    timeout;
    high_watermark;
    n_dropped = Atomic.make 0;
  }

let timeout_expired_ ~mtime ~timeout (self : _ state) : bool =
  mtime <> mtime_dummy_
  &&
  match timeout with
  | Some t ->
    let elapsed = Mtime.span mtime self.start in
    Mtime.Span.compare elapsed t >= 0
  | None -> false

(** Big enough to send? *)
let[@inline] is_full_ ~batch (self : _ state) : bool = self.size >= batch

let pop_if_ready_ ~force ~mtime (self : _ t) : _ list option =
  let rev_batch_opt =
    (* update state. When uncontended this runs only once. *)
    Util_atomic.update_cas self.st @@ fun state ->
    (* *)

    (* check if the batch is ready *)
    let ready_to_pop =
      state.size > 0
      && (force
         || is_full_ ~batch:self.batch state
         || timeout_expired_ ~mtime ~timeout:self.timeout state)
    in

    if ready_to_pop then (
      assert (state.q <> []);
      let batch = state.q in
      let new_st = _empty_state in
      Some batch, new_st
    ) else
      None, state
  in
  match rev_batch_opt with
  | None -> None
  | Some batch ->
    (* Reverse the list to retrieve the FIFO order. *)
    Some (List.rev batch)

let pop_if_ready ?(force = false) ~mtime (self : _ t) : _ list option =
  pop_if_ready_ ~force ~mtime self

let push (self : _ t) elems : [ `Dropped | `Ok ] =
  if elems = [] then
    `Ok
  else (
    let now = Mtime_clock.now () in
    let res =
      Util_atomic.update_cas self.st @@ fun state ->
      if state.size >= self.high_watermark then
        ( (* drop this to prevent queue from growing too fast *)
          `Dropped,
          state )
      else (
        let start =
          if state.size = 0 && Option.is_some self.timeout then
            now
          else
            state.start
        in

        (* add to queue *)
        let state =
          {
            size = state.size + List.length elems;
            q = List.rev_append elems state.q;
            start;
          }
        in

        `Ok, state
      )
    in
    (match res with
    | `Dropped -> Atomic.incr self.n_dropped
    | `Ok -> ());
    res
  )

let[@inline] push' self elems = ignore (push self elems : [ `Dropped | `Ok ])

let[@inline] n_dropped self = Atomic.get self.n_dropped

module Internal_ = struct
  let mtime_dummy_ = mtime_dummy_
end
