(** start a thread in the background, running [f()], blocking signals *)
let start_bg_thread (f : unit -> unit) : Thread.t =
  let unix_run () =
    let signals =
      [
        Sys.sigusr1;
        Sys.sigusr2;
        Sys.sigterm;
        Sys.sigpipe;
        Sys.sigalrm;
        Sys.sigstop;
      ]
    in
    ignore (Thread.sigmask Unix.SIG_BLOCK signals : _ list);
    f ()
  in
  (* no signals on Windows *)
  let run () =
    if Sys.win32 then
      f ()
    else
      unix_run ()
  in
  Thread.create run ()

(** thread that calls [tick()] regularly, to help enforce timeouts *)
let setup_ticker_thread ~(active : Aswitch.t) ~sleep_ms ~(tick : unit -> unit)
    () =
  let sleep_s = float sleep_ms /. 1000. in
  let tick_loop () =
    try
      while Aswitch.is_on active do
        Thread.delay sleep_s;

        if Aswitch.is_on active then tick ()
      done
    with
    | Sync_queue.Closed -> ()
    | exn ->
      (* print and ignore *)
      let bt = Printexc.get_raw_backtrace () in
      Printf.eprintf "otel: background thread: uncaught exn:\n%s\n%s\n%!"
        (Printexc.to_string exn)
        (Printexc.raw_backtrace_to_string bt)
  in
  start_bg_thread tick_loop
