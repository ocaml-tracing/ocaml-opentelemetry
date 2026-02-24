open Lwt.Syntax

(** Lwt task that calls [tick()] regularly, to help enforce timeouts.
    @param frequency_s how often in seconds does the tick tock? *)
let start_ticker_thread ?(finally = ignore) ~(stop : bool Atomic.t)
    ~(frequency_s : float) ~(tick : unit -> unit) () : unit =
  let frequency_s = max frequency_s 0.5 in
  let rec tick_loop () =
    if Atomic.get stop then (
      finally ();
      Lwt.return ()
    ) else
      let* () = Lwt_unix.sleep frequency_s in
      tick ();
      tick_loop ()
  in
  Lwt.async tick_loop
