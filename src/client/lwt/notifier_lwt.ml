(** Notification that can be used on the consumer side of a bounded queue *)

module IO = Io_lwt

type t = {
  notified: bool Atomic.t;
  cond: unit Lwt_condition.t;
  notification: Types_.notification;
  lwt_tid: int;  (** thread ID where lwt runs *)
  deleted: bool Atomic.t;
}

let create () : t =
  let notified = Atomic.make false in
  let cond = Lwt_condition.create () in
  let notification =
    Lwt_unix.make_notification (fun () ->
        Atomic.set notified false;
        Lwt_condition.broadcast cond ())
  in
  let lwt_tid = Thread.id @@ Thread.self () in
  { notified; notification; cond; lwt_tid; deleted = Atomic.make false }

let delete self : unit =
  if not (Atomic.exchange self.deleted true) then
    Lwt_unix.stop_notification self.notification

let trigger (self : t) : unit =
  let tid = Thread.id @@ Thread.self () in

  if tid = self.lwt_tid then
    (* in lwt thread, directly use the condition *)
    Lwt_condition.broadcast self.cond ()
  else if not (Atomic.exchange self.notified true) then
    Lwt_unix.send_notification self.notification

let wait (self : t) ~should_keep_waiting : unit Lwt.t =
  let open Lwt.Syntax in
  let rec loop () =
    if should_keep_waiting () then
      let* () = Lwt_condition.wait self.cond in
      loop ()
    else
      Lwt.return_unit
  in
  loop ()

let register_bounded_queue (self : t) (q : _ Bounded_queue.Recv.t) : unit =
  Bounded_queue.Recv.on_non_empty q (fun () -> trigger self)
