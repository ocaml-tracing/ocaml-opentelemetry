open Common_

type error = Export_error.t

module type IO = Generic_io.S_WITH_CONCURRENCY

module type HTTPC = sig
  module IO : IO

  type t

  val create : unit -> t

  val cleanup : t -> unit

  val send :
    t ->
    url:string ->
    headers:(string * string) list ->
    decode:[ `Dec of Pbrt.Decoder.t -> 'a | `Ret of 'a ] ->
    string ->
    ('a, error) result IO.t
end

module Make
    (IO : IO)
    (Notifier : Generic_notifier.S with type 'a IO.t = 'a IO.t)
    (Httpc : HTTPC with type 'a IO.t = 'a IO.t) : sig
  val consumer :
    ?override_n_workers:int ->
    ticker_task:float option ->
    config:Http_config.t ->
    unit ->
    Consumer.any_signal_l_builder
  (** Make a consumer builder, ie. a builder function that will take a bounded
      queue of signals, and start a consumer to process these signals and send
      them somewhere using HTTP.
      @param ticker_task
        controls whether we start a task to call [tick] at the given interval in
        seconds, or [None] to not start such a task at all. *)
end = struct
  module Sender :
    Generic_consumer.SENDER with module IO = IO and type config = Http_config.t =
  struct
    module IO = IO

    type config = Http_config.t

    type t = {
      config: config;
      encoder: Pbrt.Encoder.t;
      http: Httpc.t;
    }

    let create ~config () : t =
      { config; http = Httpc.create (); encoder = Pbrt.Encoder.create () }

    let cleanup self = Httpc.cleanup self.http

    (** Should we retry, based on the HTTP response code? *)
    let should_retry = function
      | `Failure _ -> true (* Network errors, connection issues *)
      | `Status (code, _) ->
        (* Retry on server errors, rate limits, timeouts *)
        code >= 500 || code = 429 || code = 408
      | `Sysbreak -> false (* User interrupt, don't retry *)

    (** Retry loop over [f()] with exponential backoff *)
    let rec retry_loop_ (self : t) attempt delay_ms ~f =
      let open IO in
      let* result = f () in
      match result with
      | Ok x -> return (Ok x)
      | Error err
        when should_retry err && attempt < self.config.retry_max_attempts ->
        let delay_s = delay_ms /. 1000. in
        let* () = sleep_s delay_s in
        let next_delay =
          min self.config.retry_max_delay_ms
            (delay_ms *. self.config.retry_backoff_multiplier)
        in
        retry_loop_ self (attempt + 1) next_delay ~f
      | Error _ as err -> return err

    let send (self : t) (sigs : OTEL.Any_signal_l.t) : (unit, error) result IO.t
        =
      let res = Resource_signal.of_signal_l sigs in
      let url, signal_headers =
        match res with
        | Logs _ -> self.config.url_logs, self.config.headers_logs
        | Traces _ -> self.config.url_traces, self.config.headers_traces
        | Metrics _ -> self.config.url_metrics, self.config.headers_metrics
      in
      (* Merge general headers with signal-specific ones (signal-specific takes precedence) *)
      let signal_keys = List.map fst signal_headers in
      let filtered_general =
        List.filter
          (fun (k, _) -> not (List.mem k signal_keys))
          self.config.headers
      in
      let content_type =
        match self.config.protocol with
        | Http_protobuf -> "application/x-protobuf"
        | Http_json -> "application/json"
      in
      let headers =
        ("Content-Type", content_type)
        :: ("Accept", content_type)
        :: List.rev_append signal_headers filtered_general
      in
      let data =
        Resource_signal.Encode.any ~encoder:self.encoder
          ~protocol:self.config.protocol res
      in

      let do_once () =
        Httpc.send self.http ~url ~headers ~decode:(`Ret ()) data
      in

      if self.config.retry_max_attempts > 0 then
        retry_loop_ self 0 self.config.retry_initial_delay_ms ~f:do_once
      else
        do_once ()
  end

  module C = Generic_consumer.Make (IO) (Notifier) (Sender)

  let default_n_workers = 50

  let consumer ?override_n_workers ~ticker_task ~(config : Http_config.t) () :
      Consumer.any_signal_l_builder =
    let n_workers =
      max 2
        (min 500
           (match override_n_workers, config.http_concurrency_level with
           | Some n, _ -> n
           | None, Some n -> n
           | None, None -> default_n_workers))
    in

    C.consumer ~sender_config:config ~n_workers ~ticker_task ()
end
