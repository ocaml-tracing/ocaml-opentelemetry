module T = Opentelemetry_lwt
module Atomic = Opentelemetry_atomic.Atomic
open Lwt.Syntax

let spf = Printf.sprintf

let ( let@ ) f x = f x

let sleep_inner = ref 0.1

let sleep_outer = ref 2.0

let n_jobs = ref 1

let n = ref max_int

let iterations = ref 1

let num_sleep = Atomic.make 0

let stress_alloc_ = ref true

let num_tr = Atomic.make 0

let run_job job_id : unit Lwt.t =
  let i = ref 0 in
  while%lwt T.Aswitch.is_on (T.Sdk.active ()) && !i < !n do
    (* Printf.eprintf "test: run outer loop job_id=%d i=%d\n%!" job_id !i; *)
    let@ scope =
      Atomic.incr num_tr;
      T.Tracer.with_ ~kind:T.Span.Span_kind_producer "loop.outer"
        ~attrs:[ "i", `Int !i; "job_id", `Int job_id ]
    in

    incr i;

    for%lwt j = 1 to !iterations do
      (* parent scope is found via thread local storage *)
      (* Printf.eprintf "test: run inner loop job_id=%d i=%d j=%d\n%!" job_id !i j; *)
      let@ span =
        Atomic.incr num_tr;
        T.Tracer.with_ ~parent:scope ~kind:T.Span.Span_kind_internal
          ~attrs:[ "j", `Int j ]
          "loop.inner"
      in

      let* () = Lwt_unix.sleep !sleep_outer in
      Atomic.incr num_sleep;

      T.Logger.logf ~trace_id:(T.Span.trace_id span) ~span_id:(T.Span.id span)
        ~severity:Severity_number_info (fun k -> k "inner at %d" j);
      try%lwt
        Atomic.incr num_tr;
        (* allocate some stuff *)
        let%lwt () =
          if !stress_alloc_ then (
            let@ scope =
              T.Tracer.with_ ~kind:T.Span.Span_kind_internal ~parent:span
                "alloc"
            in
            let _arr = Sys.opaque_identity @@ Array.make (25 * 25551) 42.0 in
            ignore _arr;
            T.Span.add_event scope (T.Event.make "done with alloc");
            Lwt.return ()
          ) else
            Lwt.return ()
        in

        let* () = Lwt_unix.sleep !sleep_inner in
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
  T.Gc_metrics.setup ();

  T.Meter.add_cb (fun ~clock () ->
      let now = T.Clock.now clock in
      T.Metrics.
        [
          sum ~name:"num-sleep" ~is_monotonic:true
            [ int ~now (Atomic.get num_sleep) ];
        ]);
  T.Meter.add_to_main_exporter T.Meter.default;

  let n_jobs = max 1 !n_jobs in
  (* Printf.printf "run %d jobs\n%!" n_jobs; *)

  let jobs = List.init n_jobs run_job in
  (* Printf.eprintf "test: joining jobs\n%!"; *)
  Lwt.join jobs

let () =
  Sys.catch_break true;
  T.Globals.service_name := "t1";
  T.Globals.service_namespace := Some "ocaml-otel.test";
  let ts_start = Unix.gettimeofday () in

  let debug = ref false in
  let batch_traces = ref 400 in
  let batch_metrics = ref 3 in
  let batch_logs = ref 400 in
  let self_trace = ref true in
  let url = ref None in
  let n_procs = ref 1 in
  let opts =
    [
      "--debug", Arg.Bool (( := ) debug), " enable debug output";
      ( "--url",
        Arg.String (fun s -> url := Some s),
        " set the url for the OTel collector" );
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
      ( "--iterations",
        Arg.Set_int iterations,
        " the number of inner iterations to run" );
      "-j", Arg.Set_int n_jobs, " number of parallel jobs";
      "-n", Arg.Set_int n, " number of outer iterations (default ∞)";
      "--self-trace", Arg.Bool (( := ) self_trace), " self tracing";
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
    Opentelemetry_client_cohttp_lwt.Config.make ~debug:!debug ?url:!url
      ~self_trace:!self_trace
      ~batch_traces:(some_if_nzero batch_traces)
      ~batch_metrics:(some_if_nzero batch_metrics)
      ~batch_logs:(some_if_nzero batch_logs) ()
  in
  Format.printf "@[<2>sleep outer: %.3fs,@ sleep inner: %.3fs,@ config: %a@]@."
    !sleep_outer !sleep_inner Opentelemetry_client_cohttp_lwt.Config.pp config;

  let@ () =
    Fun.protect ~finally:(fun () ->
        let elapsed = Unix.gettimeofday () -. ts_start in
        let n_per_sec = float (Atomic.get num_tr) /. elapsed in
        Printf.printf "\ndone. %d spans in %.4fs (%.4f/s)\n%!"
          (Atomic.get num_tr) elapsed n_per_sec)
  in
  Opentelemetry_client_cohttp_lwt.with_setup ~config () run |> Lwt_main.run
