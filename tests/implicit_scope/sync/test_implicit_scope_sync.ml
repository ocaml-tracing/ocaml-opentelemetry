open Alcotest
module Otel = Opentelemetry

let spans_emitted : Otel.Span.t list ref = ref []

let test_exporter : Otel.Exporter.t =
  let open Otel.Exporter in
  {
    (dummy ()) with
    emit_spans =
      Opentelemetry_emitter.To_list.to_list ~signal_name:"spans" spans_emitted;
  }

let with_test_exporter f =
  (* uncomment for eprintf debugging: *)
  (* let test_exporter = Opentelemetry_client.Exporter_debug.debug test_exporter in*)
  Otel.Main_exporter.with_setup_debug_backend test_exporter () f

let bytes_to_hex = Opentelemetry_util.Util_bytes_.bytes_to_hex

let test_stack_based_implicit_scope () =
  let run () =
    Otel.Tracer.with_ "first trace" @@ fun _scope ->
    Thread.delay 0.2;
    Otel.Tracer.with_ "second trace" @@ fun _scope ->
    Thread.delay 0.2;
    Otel.Tracer.with_ "third trace" @@ fun _scope ->
    Thread.delay 0.2;
    ()
  in
  with_test_exporter @@ fun () ->
  (* start *)
  run ();
  check' int ~msg:"count of spans emitted"
    ~actual:(List.length !spans_emitted)
    ~expected:3;
  let open Otel.Proto.Trace in
  let f prev_span_id (sp : Otel.Span.t) =
    Format.printf "%a@." pp_span sp;
    let { name; trace_id; span_id; parent_span_id; _ } = sp in
    Printf.printf
      "name='%s' trace_id='%s' span_id='%s' parent_span_id='%s' \
       prev_span_id='%s'\n"
      name (bytes_to_hex trace_id) (bytes_to_hex span_id)
      (bytes_to_hex parent_span_id)
      (bytes_to_hex prev_span_id);
    check' string ~msg:"previous span is parent"
      ~actual:(bytes_to_hex parent_span_id)
      ~expected:(bytes_to_hex prev_span_id);
    span_id
  in
  List.fold_left f (Bytes.of_string "") !spans_emitted |> ignore

let suite =
  [
    test_case "stack-based implicit scope" `Quick
      test_stack_based_implicit_scope;
  ]

let () = Alcotest.run "implicit scope" [ "sync", suite ]
