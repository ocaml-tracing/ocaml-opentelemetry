module OT = Opentelemetry
module Otel_lwt = Opentelemetry_lwt

let ( let@ ) f x = f x

let sleep_inner = ref 0.1

let sleep_outer = ref 2.0

let mk_client ~scope =
  Opentelemetry_cohttp_lwt.client ~span:scope (module Cohttp_lwt_unix.Client)

let run () =
  let open Lwt.Syntax in
  let rec go () =
    let@ scope =
      Otel_lwt.Tracer.with_ ~kind:OT.Span.Span_kind_producer "loop.outer"
    in
    let* () = Lwt_unix.sleep !sleep_outer in
    let module C = (val mk_client ~scope) in
    (* Using the same default server O  *)
    let* _res, body =
      C.get (Uri.of_string Opentelemetry_client.Http_config.default_url)
    in
    let* () = Cohttp_lwt.Body.drain_body body in
    go ()
  in
  go ()

let () =
  Sys.catch_break true;
  OT.Globals.service_name := "ocaml-otel-cohttp-client";
  OT.Globals.service_namespace := Some "ocaml-otel.test";

  let debug = ref false in
  let batch_traces = ref 400 in
  let batch_metrics = ref 3 in
  let opts =
    [
      "--debug", Arg.Bool (( := ) debug), " enable debug output";
      "--batch-traces", Arg.Int (( := ) batch_traces), " size of traces batch";
      ( "--batch-metrics",
        Arg.Int (( := ) batch_metrics),
        " size of metrics batch" );
      "--sleep-inner", Arg.Set_float sleep_inner, " sleep (in s) in inner loop";
      "--sleep-outer", Arg.Set_float sleep_outer, " sleep (in s) in outer loop";
    ]
    |> Arg.align
  in

  Arg.parse opts (fun _ -> ()) "emit1 [opt]*";

  let some_if_nzero r =
    if !r > 0 then
      Some !r
    else
      None
  in
  let config =
    Opentelemetry_client_cohttp_lwt.Config.make ~debug:!debug
      ?batch_traces:(some_if_nzero batch_traces)
      ?batch_metrics:(some_if_nzero batch_metrics)
      ()
  in
  Format.printf "@[<2>sleep outer: %.3fs,@ sleep inner: %.3fs,@ config: %a@]@."
    !sleep_outer !sleep_inner Opentelemetry_client_cohttp_lwt.Config.pp config;

  Format.printf
    "Check HTTP requests at \
     https://requestbin.com/r/enec1hql02hz/26qShWryt5vJc1JfrOwalhr5vQt@.";

  Opentelemetry_client_cohttp_lwt.with_setup ~config () run |> Lwt_main.run
