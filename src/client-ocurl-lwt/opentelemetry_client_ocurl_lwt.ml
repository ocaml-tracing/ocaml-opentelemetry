(*
   https://github.com/open-telemetry/oteps/blob/main/text/0035-opentelemetry-protocol.md
   https://github.com/open-telemetry/oteps/blob/main/text/0099-otlp-http.md
 *)

module Config = Config
open Opentelemetry
open Opentelemetry_client
open Common_

type error = Export_error.t

open struct
  module IO = Opentelemetry_client_lwt.Io_lwt
end

(** HTTP client *)
module Httpc : Generic_http_consumer.HTTPC with module IO = IO = struct
  module IO = IO
  open Lwt.Syntax

  type t = Ezcurl_core.t

  let create () : t = Ezcurl_lwt.make ()

  let cleanup self = Ezcurl_lwt.delete self

  (** send the content to the remote endpoint/path *)
  let send (self : t) ~attempt_descr ~url ~headers:user_headers ~decode
      (bod : string) : ('a, error) result Lwt.t =
    let* r =
      let headers = user_headers in
      Ezcurl_lwt.post ~client:self ~headers ~params:[] ~url
        ~content:(`String bod) ()
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
      Lwt.return @@ Error err
    | Ok { code; body; _ } when code >= 200 && code < 300 ->
      (match decode with
      | `Ret x -> Lwt.return @@ Ok x
      | `Dec f ->
        let dec = Pbrt.Decoder.of_string body in
        let r =
          try Ok (f dec)
          with e ->
            let bt = Printexc.get_backtrace () in
            Error
              (`Failure
                 (spf "decoding failed with:\n%s\n%s" (Printexc.to_string e) bt))
        in
        Lwt.return r)
    | Ok { code; body; _ } ->
      let err =
        Export_error.decode_invalid_http_response ~attempt_descr ~url ~code body
      in
      Lwt.return (Error err)
end

module Consumer_impl =
  Generic_http_consumer.Make (IO) (Opentelemetry_client_lwt.Notifier_lwt)
    (Httpc)

let create_consumer ?(config = Config.make ()) () =
  Consumer_impl.consumer ~ticker_task:(Some 0.5) ~on_tick:OTEL.Sdk.tick ~config
    ()

let create_exporter ?(config = Config.make ()) () =
  let consumer = create_consumer ~config () in
  let bq =
    Opentelemetry_client_sync.Bounded_queue_sync.create
      ~measure:OTEL.Any_signal_l.length
      ~high_watermark:Bounded_queue.Defaults.high_watermark ()
  in
  Exporter_queued.create ~clock:Clock.ptime_clock ~q:bq ~consumer ()

let create_backend = create_exporter

let setup_ ~config () : Exporter.t =
  Opentelemetry_client_lwt.Util_ambient_context.setup_ambient_context ();
  let exp = create_exporter ~config () in
  Sdk.set ~traces:config.traces ~metrics:config.metrics ~logs:config.logs exp;

  Option.iter
    (fun min_level -> Opentelemetry.Self_debug.to_stderr ~min_level ())
    config.log_level;

  Opentelemetry.Self_debug.log Opentelemetry.Self_debug.Info (fun () ->
      "opentelemetry: ocurl-lwt exporter installed");
  Opentelemetry_client.Self_trace.set_enabled config.self_trace;
  if config.self_metrics then Opentelemetry.Sdk.setup_self_metrics ();

  exp

let setup ?(config = Config.make ()) ?(enable = true) () =
  if enable && not config.sdk_disabled then
    ignore (setup_ ~config () : Exporter.t)

let remove_exporter () : unit Lwt.t =
  let done_fut, done_u = Lwt.wait () in
  Sdk.remove ~on_done:(fun () -> Lwt.wakeup_later done_u ()) ();
  done_fut

let remove_backend = remove_exporter

let with_setup ?(after_shutdown = ignore) ?(config = Config.make ())
    ?(enable = true) () f : _ Lwt.t =
  if enable && not config.sdk_disabled then
    let open Lwt.Syntax in
    let exp = setup_ ~config () in

    Lwt.catch
      (fun () ->
        let* res = f () in
        let+ () = remove_exporter () in
        after_shutdown exp;
        res)
      (fun exn ->
        let* () = remove_exporter () in
        after_shutdown exp;
        Lwt.reraise exn)
  else
    f ()
