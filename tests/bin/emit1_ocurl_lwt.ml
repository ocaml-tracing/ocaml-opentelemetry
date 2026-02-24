module OT = Opentelemetry
module Atomic = Opentelemetry_atomic.Atomic

let spf = Printf.sprintf

let ( let@ ) = ( @@ )

let sleep_inner = ref 0.1

let sleep_outer = ref 2.0

let n_jobs = ref 1

let iterations = ref 4

let n = ref max_int

let num_sleep = Atomic.make 0

let stress_alloc_ = ref true

let num_tr = Atomic.make 0

let run_job () : unit Lwt.t =
  let active = OT.Sdk.active () in
  let i = ref 0 in
  let cnt = ref 0 in

  while%lwt OT.Aswitch.is_on active && !cnt < !n do
    let@ _scope =
      Atomic.incr num_tr;
      OT.Tracer.with_ ~kind:OT.Span.Span_kind_producer "loop.outer"
        ~attrs:[ "i", `Int !i ]
    in

    (* Printf.printf "cnt=%d\n%!" !cnt; *)
    incr cnt;

    for%lwt j = 1 to !iterations do
      (* parent scope is found via thread local storage *)
      let@ span =
        Atomic.incr num_tr;
        OT.Tracer.with_ ~kind:OT.Span.Span_kind_internal ~parent:_scope
          ~attrs:[ "j", `Int j ]
          "loop.inner"
      in

      if !sleep_outer > 0. then (
        Unix.sleepf !sleep_outer;
        Atomic.incr num_sleep
      );

      OT.Logger.logf ~trace_id:(OT.Span.trace_id span)
        ~span_id:(OT.Span.id span) ~severity:Severity_number_info (fun k ->
          k "inner at %d" j);
      try%lwt
        Atomic.incr num_tr;
        (* allocate some stuff *)
        let%lwt () =
          if !stress_alloc_ then (
            let@ scope =
              OT.Tracer.with_ ~kind:OT.Span.Span_kind_internal ~parent:span
                "alloc"
            in
            let _arr = Sys.opaque_identity @@ Array.make (25 * 25551) 42.0 in
            ignore _arr;
            OT.Span.add_event scope (OT.Event.make "done with alloc");
            Lwt.return ()
          ) else
            Lwt.return ()
        in

        let%lwt () = Lwt_unix.sleep !sleep_inner in
        Atomic.incr num_sleep;

        (* simulate a failure *)
        if j = 4 && !i mod 13 = 0 then
          Lwt.fail (Failure "oh no")
        else
          Lwt.return ()
      with Failure _ -> Lwt.return ()
    done
  done
(* >>= fun () ->
   Printf.eprintf "test: job done\n%!"; 
  Lwt.return ()*)

let run () : unit Lwt.t =
  OT.Gc_metrics.setup ();

  OT.Meter.add_cb (fun ~clock:_ () -> OT.Sdk.self_metrics ());
  OT.Meter.add_cb (fun ~clock () ->
      let now = OT.Clock.now clock in
      OT.Metrics.
        [
          sum ~name:"num-sleep" ~is_monotonic:true
            [ int ~now (Atomic.get num_sleep) ];
        ]);
  OT.Meter.add_to_main_exporter OT.Meter.default;

  let n_jobs = max 1 !n_jobs in
  Printf.printf "run %d job(s)\n%!" n_jobs;

  let jobs =
    List.init n_jobs (fun _ -> try run_job () with Sys.Break -> Lwt.return ())
  in
  Lwt.join jobs

let () =
  OT.Globals.service_name := "t1";
  OT.Globals.service_namespace := Some "ocaml-otel.test";
  let ts_start = Unix.gettimeofday () in

  let debug = ref false in

  let batch_traces = ref 400 in
  let batch_metrics = ref 3 in
  let batch_logs = ref 400 in
  let self_trace = ref true in
  let final_stats = ref false in

  let n_bg_threads = ref 0 in
  let url = ref None in
  let n_procs = ref 1 in
  let opts =
    [
      "--debug", Arg.Bool (( := ) debug), " enable debug output";
      ( "--stress-alloc",
        Arg.Bool (( := ) stress_alloc_),
        " perform heavy allocs in inner loop" );
      ( "--batch-metrics",
        Arg.Int (( := ) batch_metrics),
        " size of metrics batch" );
      "--batch-traces", Arg.Int (( := ) batch_traces), " size of traces batch";
      "--batch-logs", Arg.Int (( := ) batch_logs), " size of logs batch";
      "--sleep-inner", Arg.Set_float sleep_inner, " sleep (in s) in inner loop";
      "--sleep-outer", Arg.Set_float sleep_outer, " sleep (in s) in outer loop";
      "-j", Arg.Set_int n_jobs, " number of parallel jobs";
      "--bg-threads", Arg.Set_int n_bg_threads, " number of background threads";
      "--no-self-trace", Arg.Clear self_trace, " disable self tracing";
      "-n", Arg.Set_int n, " number of iterations (default ∞)";
      ( "--iterations",
        Arg.Set_int iterations,
        " the number of inner iterations to run" );
      ( "--url",
        Arg.String (fun s -> url := Some s),
        " set the url for the OTel collector" );
      "--final-stats", Arg.Set final_stats, " display some metrics at the end";
      "--procs", Arg.Set_int n_procs, " number of processes (stub)";
    ]
    |> Arg.align
  in

  Arg.parse opts (fun _ -> ()) "emit1 [opt]*";

  if !n_procs > 1 then
    failwith
      "TODO: add support for running multiple processes to the lwt-cohttp \
       emitter";

  let some_if_nzero r =
    if !r > 0 then
      Some !r
    else
      None
  in
  let config =
    Opentelemetry_client_ocurl_lwt.Config.make ~debug:!debug
      ~self_trace:!self_trace ?url:!url
      ?http_concurrency_level:(some_if_nzero n_bg_threads)
      ~batch_traces:(some_if_nzero batch_traces)
      ~batch_metrics:(some_if_nzero batch_metrics)
      ~batch_logs:(some_if_nzero batch_logs) ()
  in
  Format.printf "@[<2>sleep outer: %.3fs,@ sleep inner: %.3fs,@ config: %a@]@."
    !sleep_outer !sleep_inner Opentelemetry_client_ocurl_lwt.Config.pp config;

  let finally () =
    let elapsed = Unix.gettimeofday () -. ts_start in
    let n_per_sec = float (Atomic.get num_tr) /. elapsed in
    Printf.printf "\ndone. %d spans in %.4fs (%.4f/s)\n%!" (Atomic.get num_tr)
      elapsed n_per_sec
  in
  let after_exp_shutdown exp =
    (* print some stats *)
    if !final_stats then (
      let ms = OT.Exporter.self_metrics exp in
      Format.eprintf "@[exporter metrics:@ %a@]@."
        (Format.pp_print_list Opentelemetry.Metrics.pp)
        ms
    )
  in

  let@ () = Fun.protect ~finally in
  Lwt_main.run
    (Opentelemetry_client_ocurl_lwt.with_setup ~config () run
       ~after_shutdown:after_exp_shutdown)
