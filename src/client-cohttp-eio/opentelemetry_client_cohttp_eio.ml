(*
   https://github.com/open-telemetry/oteps/blob/main/text/0035-opentelemetry-protocol.md
   https://github.com/open-telemetry/oteps/blob/main/text/0099-otlp-http.md
 *)

module Config = Config
open Opentelemetry
open Opentelemetry_client

let spf = Printf.sprintf

module Make (CTX : sig
  val sw : Eio.Switch.t

  val env : Eio_unix.Stdenv.base
end) =
struct
  module IO : Generic_io.S_WITH_CONCURRENCY with type 'a t = 'a = struct
    include Generic_io.Direct_style

    (* NOTE: This is only used in the main consumer thread, even though producers
      might be in other domains *)

    let sleep_s n = Eio.Time.sleep CTX.env#clock n

    let spawn f = Eio.Fiber.fork ~sw:CTX.sw f
  end

  module Notifier : Generic_notifier.S with module IO = IO = struct
    module IO = IO

    type t = {
      mutex: Eio.Mutex.t;
      cond: Eio.Condition.t;
    }

    let create () : t =
      { mutex = Eio.Mutex.create (); cond = Eio.Condition.create () }

    let trigger self =
      (* Eio.Condition.broadcast is lock-free since eio 0.8 (ocaml-multicore/eio#397)
         and safe to call from other threads/domains and signal handlers. *)
      Eio.Condition.broadcast self.cond

    let delete self =
      trigger self;
      ()

    let wait self ~should_keep_waiting =
      Eio.Mutex.lock self.mutex;
      while should_keep_waiting () do
        Eio.Condition.await self.cond self.mutex
      done;
      Eio.Mutex.unlock self.mutex

    (** Ensure we get signalled when the queue goes from empty to non-empty *)
    let register_bounded_queue (self : t) (bq : _ Bounded_queue.Recv.t) : unit =
      Bounded_queue.Recv.on_non_empty bq (fun () -> trigger self)
  end

  module Httpc : Generic_http_consumer.HTTPC with module IO = IO = struct
    module IO = IO
    open Opentelemetry.Proto
    module Httpc = Cohttp_eio.Client

    type t = Httpc.t

    let authenticator =
      match Ca_certs.authenticator () with
      | Ok x -> x
      | Error (`Msg m) ->
        Fmt.failwith "Failed to create system store X509 authenticator: %s" m

    let https ~authenticator =
      let tls_config =
        match Tls.Config.client ~authenticator () with
        | Error (`Msg msg) -> failwith ("tls configuration problem: " ^ msg)
        | Ok tls_config -> tls_config
      in
      fun uri raw ->
        let host =
          Uri.host uri
          |> Option.map (fun x -> Domain_name.(host_exn (of_string_exn x)))
        in
        Tls_eio.client_of_flow ?host tls_config raw

    let create () = Httpc.make ~https:(Some (https ~authenticator)) CTX.env#net

    let cleanup = ignore

    (* send the content to the remote endpoint/path *)
    let send (client : t) ~url ~headers:user_headers ~decode (body : string) :
        ('a, Export_error.t) result =
      Eio.Switch.run @@ fun sw ->
      let uri = Uri.of_string url in

      let open Cohttp in
      let headers = Header.(add_list (init ()) user_headers) in

      let body = Cohttp_eio.Body.of_string body in
      let r =
        try
          let r = Httpc.post client ~sw ~headers ~body uri in
          Ok r
        with e -> Error e
      in
      match r with
      | Error e ->
        let err =
          `Failure
            (spf "sending signals via http POST to %S\nfailed with:\n%s" url
               (Printexc.to_string e))
        in
        Error err
      | Ok (resp, body) ->
        let body =
          Eio.Buf_read.(parse_exn take_all) body ~max_size:(10 * 1024 * 1024)
        in
        let code = Response.status resp |> Code.code_of_status in
        if not (Code.is_error code) then (
          match decode with
          | `Ret x -> Ok x
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
            r
        ) else (
          let dec = Pbrt.Decoder.of_string body in

          let r =
            try
              let status = Status.decode_pb_status dec in
              Error (`Status (code, status))
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
          r
        )
  end
end

let create_consumer ?(config = Config.make ()) ~sw ~env () :
    _ Consumer.Builder.t =
  let module M = Make (struct
    let sw = sw

    let env = env
  end) in
  let module C = Generic_http_consumer.Make (M.IO) (M.Notifier) (M.Httpc) in
  C.consumer ~ticker_task:(Some 0.5) ~on_tick:Sdk.tick ~config ()

let create_exporter ?(config = Config.make ()) ~sw ~env () =
  let consumer = create_consumer ~config ~sw ~env () in
  let bq =
    Opentelemetry_client_sync.Bounded_queue_sync.create
      ~high_watermark:Bounded_queue.Defaults.high_watermark ()
  in
  Exporter_queued.create ~clock:Clock.ptime_clock ~q:bq ~consumer ()

let create_backend = create_exporter

let setup_ ~sw ~config env : unit =
  Opentelemetry_ambient_context.set_current_storage Ambient_context_eio.storage;
  let exp = create_exporter ~config ~sw ~env () in
  Sdk.set ?batch_traces:config.batch_traces ?batch_metrics:config.batch_metrics
    ?batch_logs:config.batch_logs
    ~batch_timeout:Mtime.Span.(config.batch_timeout_ms * ms)
    exp

let setup ?(config = Config.make ()) ?(enable = true) ~sw env =
  if enable && not config.sdk_disabled then setup_ ~sw ~config env

let remove_exporter () =
  let p, waker = Eio.Promise.create () in
  Sdk.remove () ~on_done:(fun () -> Eio.Promise.resolve waker ());
  Eio.Promise.await p

let remove_backend = remove_exporter

let with_setup ?(config = Config.make ()) ?(enable = true) env f =
  if enable && not config.sdk_disabled then (
    Eio.Switch.run @@ fun sw ->
    setup_ ~sw ~config env;
    Fun.protect f ~finally:remove_exporter
  ) else
    f ()
