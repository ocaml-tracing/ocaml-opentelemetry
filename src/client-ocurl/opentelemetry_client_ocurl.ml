(*
   https://github.com/open-telemetry/oteps/blob/main/text/0035-opentelemetry-protocol.md
   https://github.com/open-telemetry/oteps/blob/main/text/0099-otlp-http.md
 *)

module Config = Config
module OTELC = Opentelemetry_client
module OTEL = Opentelemetry
open Common_

type error = OTELC.Export_error.t

open struct
  module Notifier = Opentelemetry_client_sync.Notifier_sync
  module IO = Opentelemetry_client_sync.Io_sync
end

module Httpc : OTELC.Generic_http_consumer.HTTPC with module IO = IO = struct
  module IO = IO

  type t = Ezcurl_core.t

  let create () = Ezcurl.make ()

  let cleanup = Ezcurl.delete

  let send (self : t) ~url ~headers:user_headers ~decode (bod : string) :
      ('a, error) result =
    let r =
      let headers = user_headers in
      Ezcurl.post ~client:self ~headers ~params:[] ~url ~content:(`String bod)
        ()
    in
    match r with
    | Error (code, msg) ->
      let err =
        `Failure
          (spf
             "sending signals via http POST failed:\n\
             \  %s\n\
             \  curl code: %s\n\
             \  url: %s\n\
              %!"
             msg (Curl.strerror code) url)
      in
      Error err
    | Ok { code; body; _ } when code >= 200 && code < 300 ->
      (match decode with
      | `Ret x -> Ok x
      | `Dec f ->
        let dec = Pbrt.Decoder.of_string body in
        (try Ok (f dec)
         with e ->
           let bt = Printexc.get_backtrace () in
           Error
             (`Failure
                (spf "decoding failed with:\n%s\n%s" (Printexc.to_string e) bt))))
    | Ok { code; body; _ } ->
      let err =
        OTELC.Export_error.decode_invalid_http_response ~url ~code body
      in
      Error err
end

module Consumer_impl = OTELC.Generic_http_consumer.Make (IO) (Notifier) (Httpc)

let consumer ?(config = Config.make ()) () :
    Opentelemetry_client.Consumer.any_signal_l_builder =
  let n_workers = max 2 (min 32 config.bg_threads) in
  let ticker_task =
    if config.ticker_thread then
      Some (float config.ticker_interval_ms /. 1000.)
    else
      None
  in
  Consumer_impl.consumer ~override_n_workers:n_workers ~on_tick:OTEL.Sdk.tick
    ~ticker_task ~config:config.common ()

let create_exporter ?(config = Config.make ()) () : OTEL.Exporter.t =
  let consumer = consumer ~config () in
  let bq =
    Opentelemetry_client_sync.Bounded_queue_sync.create
      ~high_watermark:OTELC.Bounded_queue.Defaults.high_watermark ()
  in

  OTELC.Exporter_queued.create ~clock:OTEL.Clock.ptime_clock ~q:bq ~consumer ()

let create_backend = create_exporter

let setup_ ~config () : OTEL.Exporter.t =
  let exporter = create_exporter ~config () in
  OTEL.Sdk.set ?batch_traces:config.common.batch_traces
    ?batch_metrics:config.common.batch_metrics
    ?batch_logs:config.common.batch_logs
    ~batch_timeout:Mtime.Span.(config.common.batch_timeout_ms * ms)
    exporter;

  OTELC.Self_trace.set_enabled config.common.self_trace;
  exporter

let remove_exporter () : unit =
  let open Opentelemetry_client_sync in
  (* used to wait *)
  let sq = Sync_queue.create () in
  OTEL.Sdk.remove () ~on_done:(fun () -> Sync_queue.push sq ());
  Sync_queue.pop sq

let remove_backend = remove_exporter

let setup ?(config : Config.t = Config.make ()) ?(enable = true) () =
  if enable && not config.common.sdk_disabled then
    ignore (setup_ ~config () : OTEL.Exporter.t)

let with_setup ?(after_shutdown = ignore) ?(config : Config.t = Config.make ())
    ?(enable = true) () f =
  if enable && not config.common.sdk_disabled then (
    let exp = setup_ ~config () in
    Fun.protect f ~finally:(fun () ->
        remove_exporter ();
        after_shutdown exp)
  ) else
    f ()
