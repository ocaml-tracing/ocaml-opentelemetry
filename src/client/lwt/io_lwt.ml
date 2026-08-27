type 'a t = 'a Lwt.t

let return = Lwt.return

let ( let* ) = Lwt.Syntax.( let* )

let sleep_s = Lwt_unix.sleep

let spawn = Lwt.async

(* no cancellation of a pending [Lwt_unix.sleep] to offer here *)
let spawn_daemon = spawn

let[@inline] protect ~finally f = Lwt.finalize f finally
