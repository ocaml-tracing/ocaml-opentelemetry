(** This library defines a set of tests expecting that are meant to be run on an
    application whick emits a set of signals that is isomorphic to those emitted
    by the ../bin/emit1_cohttp.ml and ../bin/emit1_eio.ml executables. *)

module Client = Opentelemetry_client
module Proto = Opentelemetry.Proto
open Containers

let batch_size : Client.Resource_signal.t -> int = function
  | Traces ts -> List.length ts
  | Logs ls -> List.length ls
  | Metrics ms -> List.length ms

let avg_batch_size (p : Client.Resource_signal.t -> bool)
    (batches : Client.Resource_signal.t list) : int =
  let sum =
    List.fold_left
      (fun acc b ->
        if p b then
          acc + batch_size b
        else
          acc)
      0 batches
  in
  sum / List.length batches

let signals_from_batch (signal_batch : Client.Resource_signal.t) =
  match signal_batch with
  | Traces ts -> List.map (fun t -> `Trace t) ts
  | Logs ls -> List.map (fun l -> `Log l) ls
  | Metrics ms -> List.map (fun m -> `Metric m) ms

let filter_map_spans f signals =
  signals
  |> CCList.flat_map (function
    | `Log _ | `Metric _ -> []
    | `Trace (r : Proto.Trace.resource_spans) ->
      r.scope_spans
      |> CCList.flat_map (fun ss -> ss.Proto.Trace.spans |> List.filter_map f))

let count_spans_with_name name signals =
  signals
  |> filter_map_spans (fun s ->
      if String.equal s.Proto.Trace.name name then
        Some s
      else
        None)
  |> List.length

let filter_map_metrics f signals =
  signals
  |> CCList.flat_map (function
    | `Log _ | `Trace _ -> []
    | `Metric (r : Proto.Metrics.resource_metrics) ->
      r.scope_metrics
      |> CCList.flat_map (fun ss ->
          ss.Proto.Metrics.metrics |> List.filter_map f))

let count_metrics_with_name name signals =
  signals
  |> filter_map_metrics (fun s ->
      if String.equal s.Proto.Metrics.name name then
        Some s
      else
        None)
  |> List.length

let number_data_point_to_float : Proto.Metrics.number_data_point_value -> float
    = function
  | Proto.Metrics.As_double f -> f
  | Proto.Metrics.As_int i64 -> Int64.to_float i64

let get_metric_values name signals =
  signals
  |> filter_map_metrics (fun (m : Proto.Metrics.metric) ->
      if not (String.equal m.name name) then
        None
      else
        Option.some
        @@
        match m.data with
        | Some (Sum { data_points; is_monotonic = true; _ }) ->
          List.fold_left
            (fun acc (p : Proto.Metrics.number_data_point) ->
              acc
              +. CCOption.map_or ~default:0. number_data_point_to_float p.value)
            0. data_points
        | _ -> failwith "TODO: Support for getting other metrics")

let filter_map_logs (f : Proto.Logs.log_record -> 'a option) signals : 'a list =
  signals
  |> CCList.flat_map (function
    | `Metric _ | `Trace _ -> []
    | `Log (r : Proto.Logs.resource_logs) ->
      r.scope_logs
      |> CCList.flat_map (fun ss ->
          ss.Proto.Logs.log_records |> List.filter_map f))

let count_logs_with_body p signals =
  signals
  |> filter_map_logs (fun (l : Proto.Logs.log_record) ->
      if p l.body then
        Some ()
      else
        None)
  |> List.length

type params = {
  url: string;
  jobs: int;
  procs: int;
  n_outer: int;
  batch_traces: int;
  batch_metrics: int;
  batch_logs: int;
  iterations: int;
}

let cmd exec params : string list =
  [
    exec;
    "-j";
    string_of_int params.jobs;
    "--procs";
    string_of_int params.procs;
    "--url";
    params.url;
    "-n";
    string_of_int params.n_outer;
    "--iterations";
    string_of_int params.iterations;
    "--batch-traces";
    string_of_int params.batch_traces;
    "--batch-metrics";
    string_of_int params.batch_metrics;
    "--batch-logs";
    string_of_int params.batch_logs;
  ]

let test name f = Alcotest.test_case name `Quick f

let tests params signal_batches =
  let signals =
    signal_batches
    |> List.fold_left
         (fun acc b -> List.rev_append (signals_from_batch b) acc)
         []
  in
  [
    (* TODO: What properties of batch sizes does it make sense to test? *)
    test "loop.outer spans" (fun () ->
        Alcotest.(check' int)
          ~msg:
            "number of occurrences should equal the configured jobs * the \
             configured processes"
          ~expected:(params.jobs * params.procs * params.n_outer)
          ~actual:(count_spans_with_name "loop.outer" signals));
    test "loop.inner spans" (fun () ->
        Alcotest.(check' int)
          ~msg:
            "number of occurrences should equal the configured jobs * the  \
             configured iterations * configured processes"
          ~expected:
            (params.jobs * params.iterations * params.procs * params.n_outer)
          ~actual:(count_spans_with_name "loop.inner" signals));
    test "alloc spans" (fun () ->
        Alcotest.(check' int)
          ~msg:
            "number of occurrences should equal the configured jobs * the  \
             configured iterations * configured processes"
          ~expected:
            (params.jobs * params.iterations * params.procs * params.n_outer)
          ~actual:(count_spans_with_name "alloc" signals);
        Alcotest.(check' bool)
          ~msg:"should have 'done with alloc' event" ~expected:true
          ~actual:
            (let all_alloc_events =
               signals
               |> filter_map_spans (fun s ->
                   if not (String.equal s.name "alloc") then
                     Some s.events
                   else
                     None)
               |> List.flatten
             in
             all_alloc_events
             |> List.for_all (fun (e : Proto.Trace.span_event) ->
                 String.equal e.name "done with alloc")));
    test "num-sleep metrics" (fun () ->
        Alcotest.(check' bool)
          ~msg:
            "should record at lest as many sleep metrics as there are \
             iterations configured"
          ~expected:true
          ~actual:
            (count_metrics_with_name "num-sleep" signals >= params.iterations));
    test "logs" (fun () ->
        Alcotest.(check' int)
          ~msg:
            "should record jobs * iterations occurrences * configured * n \
             processes of 'inner at n'"
          ~expected:
            (params.jobs * params.iterations * params.procs * params.n_outer)
          ~actual:
            (signals
            |> count_logs_with_body (function
              | Some (Proto.Common.String_value s)
                when String.prefix ~pre:"inner at" s ->
                true
              | _ -> false)));
  ]

let run_tests ~port (cmds : _ list) : unit =
  let suites =
    let open Lwt.Syntax in
    Lwt_main.run
    @@ Lwt_list.map_s
         (fun (exec, params) ->
           let cmd = cmd exec params in
           let name = Printf.sprintf "'test: %s'" (String.concat " " cmd) in
           let* signal_batches = Signal_gatherer.gather_signals ~port cmd in
           (* Let server reset *)
           let* () = Lwt_unix.sleep 1. in
           Lwt.return (name, tests params signal_batches))
         cmds
  in
  let open Alcotest in
  run "Collector integration tests" suites
