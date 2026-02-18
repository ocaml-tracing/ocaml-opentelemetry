(** Emitter that stores signals into a list, in reverse order (most recent
    signals first). *)
let to_list ~signal_name (l : 'a list ref) : 'a Emitter.t =
  let closed_ = Atomic.make false in
  let enabled = fun () -> not (Atomic.get closed_) in
  let emit =
   fun sigs ->
    if Atomic.get closed_ then raise Emitter.Closed;
    l := List.rev_append sigs !l
  in
  let closed () = Atomic.get closed_ in
  let flush_and_close = fun () -> Atomic.set closed_ true in
  Emitter.make ~signal_name ~emit ~enabled ~closed ~flush_and_close ()
