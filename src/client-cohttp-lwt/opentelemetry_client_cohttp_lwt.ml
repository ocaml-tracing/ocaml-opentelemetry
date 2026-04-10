(*
   https://github.com/open-telemetry/oteps/blob/main/text/0035-opentelemetry-protocol.md
   https://github.com/open-telemetry/oteps/blob/main/text/0099-otlp-http.md
 *)

module Config = Config
open Opentelemetry_client
open Opentelemetry
open Common_

type error = Export_error.t

open struct
  module IO = Opentelemetry_client_lwt.Io_lwt
end

module Httpc : Generic_http_consumer.HTTPC with module IO = IO = struct
  module IO = IO
  open Opentelemetry.Proto
  open Lwt.Syntax
  module Httpc = Cohttp_lwt_unix.Client

  type t = unit

  let create () : t = ()

  let cleanup _self = ()

  (* send the content to the remote endpoint/path *)
  let send (_self : t) ~attempt_descr ~url ~headers:user_headers ~decode
      (bod : string) : ('a, error) result Lwt.t =
    let uri = Uri.of_string url in

    let open Cohttp in
    let headers = Header.(add_list (init ()) user_headers) in

    let body = Cohttp_lwt.Body.of_string bod in

    let* r =
      try%lwt
        let+ r = Httpc.post ~headers ~body uri in
        Ok r
      with e -> Lwt.return @@ Error e
    in
    match r with
    | Error e ->
      let err =
        `Failure
          (spf "sending signals via http POST to %S\nfailed with:\n%s" url
             (Printexc.to_string e))
      in
      Lwt.return @@ Error err
    | Ok (resp, body) ->
      let* body = Cohttp_lwt.Body.to_string body in
      let code = Response.status resp |> Code.code_of_status in
      if not (Code.is_error code) then (
        match decode with
        | `Ret x -> Lwt.return @@ Ok x
        | `Dec f ->
          let dec = Pbrt.Decoder.of_string body in
          let r =
            try Ok (f dec)
            with e ->
              let bt = Printexc.get_backtrace () in
              Error
                (`Failure
                   (spf "decoding failed with:\n%s\n%s" (Printexc.to_string e)
                      bt))
          in
          Lwt.return r
      ) else (
        let dec = Pbrt.Decoder.of_string body in

        let r =
          try
            let status = Status.decode_pb_status dec in
            Error (`Status (code, status, attempt_descr))
          with e ->
            let bt = Printexc.get_backtrace () in
            Error
              (`Failure
                 (spf
                    "httpc: decoding of status (url=%S, code=%d) failed with:\n\
                     %s\n\
                     status: %S\n\
                     %s"
                    url code (Printexc.to_string e) body bt))
        in
        Lwt.return r
      )
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

let setup_ ~config () : unit =
  Opentelemetry_client_lwt.Util_ambient_context.setup_ambient_context ();
  let exp = create_exporter ~config () in
  Sdk.set ~traces:config.traces ~metrics:config.metrics ~logs:config.logs exp;

  Option.iter
    (fun min_level -> Opentelemetry.Self_debug.to_stderr ~min_level ())
    config.log_level;

  Opentelemetry.Self_debug.log Opentelemetry.Self_debug.Info (fun () ->
      "opentelemetry: cohttp-lwt exporter installed");
  Opentelemetry_client.Self_trace.set_enabled config.self_trace;
  if config.self_metrics then Opentelemetry.Sdk.setup_self_metrics ();
  ()

let setup ?(config = Config.make ()) ?(enable = true) () =
  if enable && not config.sdk_disabled then setup_ ~config ()

let remove_exporter () : unit Lwt.t =
  let done_fut, done_u = Lwt.wait () in
  (* Printf.eprintf "otel.client.cohttp-lwt: removing…\n%!"; *)
  Sdk.remove
    ~on_done:(fun () ->
      (* Printf.eprintf "otel.client.cohttp-lwt: done removing\n%!"; *)
      Lwt.wakeup_later done_u ())
    ();
  done_fut

let remove_backend = remove_exporter

let with_setup ?(config = Config.make ()) ?(enable = true) () f : _ Lwt.t =
  if enable && not config.sdk_disabled then (
    setup_ ~config ();

    Lwt.finalize f remove_exporter
  ) else
    f ()
