module OT = Opentelemetry
module OTC = Opentelemetry_client

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

let run_job () =
  let active = OT.Sdk.active () in
  let i = ref 0 in
  let cnt = ref 0 in

  while OT.Aswitch.is_on active && !cnt < !n do
    let@ _scope =
      Atomic.incr num_tr;
      OT.Tracer.with_ ~kind:OT.Span.Span_kind_producer "loop.outer"
        ~attrs:[ "i", `Int !i ]
    in

    (* Printf.printf "cnt=%d\n%!" !cnt; *)
    incr cnt;

    for j = 1 to !iterations do
      (* parent scope is found via thread local storage *)
      let@ scope =
        Atomic.incr num_tr;
        OT.Tracer.with_ ~kind:OT.Span.Span_kind_internal ~parent:_scope
          ~attrs:[ "j", `Int j ]
          "loop.inner"
      in

      if !sleep_outer > 0. then (
        Unix.sleepf !sleep_outer;
        Atomic.incr num_sleep
      );

      OT.Logger.logf ~trace_id:(OT.Span.trace_id scope)
        ~span_id:(OT.Span.id scope) ~severity:Severity_number_info (fun k ->
          k "inner at %d" j);

      incr i;

      try
        Atomic.incr num_tr;
        (* allocate some stuff *)
        (if !stress_alloc_ then
           let@ _ =
             OT.Tracer.with_ ~kind:OT.Span.Span_kind_internal ~parent:scope
               "alloc"
           in
           let _arr : _ array =
             Sys.opaque_identity @@ Array.make (25 * 25551) 42.0
           in
           ignore _arr);

        if !sleep_inner > 0. then (
          Unix.sleepf !sleep_inner;
          Atomic.incr num_sleep
        );

        if j = 4 && !i mod 13 = 0 then failwith "oh no";

        (* simulate a failure *)
        OT.Span.add_event scope (OT.Event.make "done with alloc")
      with Failure _ -> ()
    done
  done;
  (* Printf.eprintf "emit1.run_job: exit\n%!"; *)
  ()

let run () =
  OT.Gc_metrics.setup ();

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
    Array.init n_jobs (fun _ ->
        let job () = try run_job () with Sys.Break -> () in
        Thread.create job ())
  in
  Array.iter Thread.join jobs

module Consumer_exporter =
  OTC.Generic_consumer_exporter.Make
    (Opentelemetry_client_sync.Io_sync)
    (Opentelemetry_client_sync.Notifier_sync)

let () =
  OT.Globals.service_name := "t1";
  OT.Globals.service_namespace := Some "ocaml-otel.test";
  let ts_start = Unix.gettimeofday () in

  let debug = ref false in

  let batch_traces = ref 400 in
  let batch_metrics = ref 3 in
  let batch_logs = ref 400 in
  let queued = ref false in
  let self_trace = ref true in

  let n_bg_threads = ref 0 in
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
      "-n", Arg.Set_int n, " number of outer iterations (default ∞)";
      ( "--iterations",
        Arg.Set_int iterations,
        " the number of inner iterations to run" );
      "--queued", Arg.Set queued, " queue exporter";
    ]
    |> Arg.align
  in

  Arg.parse opts (fun _ -> ()) "emit1 [opt]*";

  Format.printf "@[<2>sleep outer: %.3fs,@ sleep inner: %.3fs,@ queued: %b@]@."
    !sleep_outer !sleep_inner !queued;

  let exporter, finally =
    let exp = OTC.Exporter_stdout.stdout () in
    if !queued then (
      let q =
        Opentelemetry_client_sync.Bounded_queue_sync.create
          ~high_watermark:20_000 ()
      in
      let exp =
        OTC.Exporter_queued.create ~clock:OT.Clock.ptime_clock ~q
          ~consumer:(Consumer_exporter.consumer exp)
          ()
      in
      let finally () = Opentelemetry_client_sync.Shutdown_sync.shutdown exp in
      exp, finally
    ) else
      exp, ignore
  in

  OT.Sdk.set exporter;
  let@ () = Fun.protect ~finally in

  if !self_trace then Opentelemetry_client.Self_trace.set_enabled true;

  let@ () =
    Fun.protect ~finally:(fun () ->
        let elapsed = Unix.gettimeofday () -. ts_start in
        let n_per_sec = float (Atomic.get num_tr) /. elapsed in
        Printf.printf "\ndone. %d spans in %.4fs (%.4f/s)\n%!"
          (Atomic.get num_tr) elapsed n_per_sec)
  in
  run ()
