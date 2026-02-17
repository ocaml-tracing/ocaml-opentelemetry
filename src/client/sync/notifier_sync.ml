module IO = Generic_io.Direct_style

type t = {
  mutex: Mutex.t;
  cond: Condition.t;
}

let create () : t = { mutex = Mutex.create (); cond = Condition.create () }

let[@inline] trigger self = Condition.broadcast self.cond

let delete = ignore

let wait self ~should_keep_waiting =
  Mutex.lock self.mutex;
  while should_keep_waiting () do
    Condition.wait self.cond self.mutex
  done;
  Mutex.unlock self.mutex

(** Ensure we get signalled when the queue goes from empty to non-empty *)
let register_bounded_queue (self : t) (bq : _ Bounded_queue.Recv.t) : unit =
  Bounded_queue.Recv.on_non_empty bq (fun () -> trigger self)
