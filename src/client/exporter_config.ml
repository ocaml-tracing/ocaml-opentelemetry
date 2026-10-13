type protocol =
  | Http_protobuf
  | Http_json

type log_level = Opentelemetry.Self_debug.level option

type rest = unit

type t = {
  debug: bool;
  log_level: log_level;
  sdk_disabled: bool;
  url_traces: string;
  url_metrics: string;
  url_logs: string;
  headers: (string * string) list;
  headers_traces: (string * string) list;
  headers_metrics: (string * string) list;
  headers_logs: (string * string) list;
  protocol: protocol;
  timeout_ms: int;
  timeout_traces_ms: int;
  timeout_metrics_ms: int;
  timeout_logs_ms: int;
  traces: Opentelemetry.Provider_config.t;
  metrics: Opentelemetry.Provider_config.t;
  logs: Opentelemetry.Provider_config.t;
  self_trace: bool;
  self_metrics: bool;
  http_concurrency_level: int option;
  retry_max_attempts: int;
  retry_initial_delay_ms: float;
  retry_max_delay_ms: float;
  retry_backoff_multiplier: float;
  sampler: Opentelemetry.Trace_sampler.t option;
  _rest: rest;
}

open struct
  let ppiopt out i =
    match i with
    | None -> Format.fprintf out "None"
    | Some i -> Format.fprintf out "%d" i

  let pp_header ppf (a, b) = Format.fprintf ppf "@[%s: @,%s@]@." a b

  let ppheaders out l =
    Format.fprintf out "[@[%a@]]" (Format.pp_print_list pp_header) l

  let pp_protocol out = function
    | Http_protobuf -> Format.fprintf out "http/protobuf"
    | Http_json -> Format.fprintf out "http/json"

  let pp_log_level out = function
    | None -> Format.fprintf out "none"
    | Some level ->
      Format.fprintf out "%s" (Opentelemetry.Self_debug.string_of_level level)

  let pp_provider_config out (c : Opentelemetry.Provider_config.t) =
    Format.fprintf out "{batch=%a;@ timeout=%a}" ppiopt c.batch Mtime.Span.pp
      c.timeout
end

let pp out (self : t) : unit =
  let {
    debug;
    log_level;
    sdk_disabled;
    self_trace;
    self_metrics;
    url_traces;
    url_metrics;
    url_logs;
    headers;
    headers_traces;
    headers_metrics;
    headers_logs;
    protocol;
    timeout_ms;
    timeout_traces_ms;
    timeout_metrics_ms;
    timeout_logs_ms;
    traces;
    metrics;
    logs;
    http_concurrency_level;
    retry_max_attempts;
    retry_initial_delay_ms;
    retry_max_delay_ms;
    retry_backoff_multiplier;
    sampler;
    _rest = _;
  } =
    self
  in
  Format.fprintf out
    "{@[ debug=%B;@ log_level=%a;@ sdk_disabled=%B;@ self_trace=%B;@ \
     self_metrics=%B;@ url_traces=%S;@ url_metrics=%S;@ url_logs=%S;@ \
     @[<2>headers=@,\
     %a@];@ @[<2>headers_traces=@,\
     %a@];@ @[<2>headers_metrics=@,\
     %a@];@ @[<2>headers_logs=@,\
     %a@];@ protocol=%a;@ timeout_ms=%d;@ timeout_traces_ms=%d;@ \
     timeout_metrics_ms=%d;@ timeout_logs_ms=%d;@ traces=%a;@ metrics=%a;@ \
     logs=%a;@ http_concurrency_level=%a;@ retry_max_attempts=%d;@ \
     retry_initial_delay_ms=%.0f;@ retry_max_delay_ms=%.0f;@ \
     retry_backoff_multiplier=%.1f;@ sampler=%a @]}"
    debug pp_log_level log_level sdk_disabled self_trace self_metrics url_traces
    url_metrics url_logs ppheaders headers ppheaders headers_traces ppheaders
    headers_metrics ppheaders headers_logs pp_protocol protocol timeout_ms
    timeout_traces_ms timeout_metrics_ms timeout_logs_ms pp_provider_config
    traces pp_provider_config metrics pp_provider_config logs ppiopt
    http_concurrency_level retry_max_attempts retry_initial_delay_ms
    retry_max_delay_ms retry_backoff_multiplier
    (Format.pp_print_option
       ~none:(fun out () -> Format.fprintf out "none")
       Opentelemetry.Trace_sampler.pp)
    sampler

let default_url = "http://localhost:4318"

type 'k make =
  ?debug:bool ->
  ?log_level:log_level ->
  ?sdk_disabled:bool ->
  ?url:string ->
  ?url_traces:string ->
  ?url_metrics:string ->
  ?url_logs:string ->
  ?batch_traces:int ->
  ?batch_metrics:int ->
  ?batch_logs:int ->
  ?batch_timeout_ms:int ->
  ?traces:Opentelemetry.Provider_config.t ->
  ?metrics:Opentelemetry.Provider_config.t ->
  ?logs:Opentelemetry.Provider_config.t ->
  ?headers:(string * string) list ->
  ?headers_traces:(string * string) list ->
  ?headers_metrics:(string * string) list ->
  ?headers_logs:(string * string) list ->
  ?protocol:protocol ->
  ?timeout_ms:int ->
  ?timeout_traces_ms:int ->
  ?timeout_metrics_ms:int ->
  ?timeout_logs_ms:int ->
  ?self_trace:bool ->
  ?self_metrics:bool ->
  ?http_concurrency_level:int ->
  ?retry_max_attempts:int ->
  ?retry_initial_delay_ms:float ->
  ?retry_max_delay_ms:float ->
  ?retry_backoff_multiplier:float ->
  ?sampler:Opentelemetry.Trace_sampler.t ->
  'k

module type ENV = sig
  val make : (t -> 'a) -> 'a make
end

open struct
  let get_debug_from_env () =
    match Sys.getenv_opt "OTEL_OCAML_DEBUG" with
    | Some ("1" | "true") -> true
    | _ -> false

  let get_log_level_from_env () : log_level =
    match Sys.getenv_opt "OTEL_LOG_LEVEL" with
    | Some "none" -> None
    | Some "error" -> Some Error
    | Some "warn" -> Some Warning
    | Some "info" -> Some Info
    | Some "debug" -> Some Debug
    | Some s ->
      Opentelemetry.Self_debug.log Warning (fun () ->
          Printf.sprintf "unknown log level %S, defaulting to info" s);
      Some Info
    | None ->
      if get_debug_from_env () then
        Some Debug
      else
        Some Info

  let get_sdk_disabled_from_env () =
    match Sys.getenv_opt "OTEL_SDK_DISABLED" with
    | Some ("true" | "1") -> true
    | _ -> false

  let get_protocol_from_env env_name =
    match Sys.getenv_opt env_name with
    | Some "http/protobuf" -> Http_protobuf
    | Some "http/json" -> Http_json
    | _ -> Http_protobuf

  let get_timeout_from_env env_name default =
    match Sys.getenv_opt env_name with
    | Some s -> (try int_of_string s with _ -> default)
    | None -> default

  let make_get_from_env env_name =
    let value = ref None in
    fun () ->
      match !value with
      | None ->
        value := Sys.getenv_opt env_name;
        !value
      | Some value -> Some value

  let get_url_from_env = make_get_from_env "OTEL_EXPORTER_OTLP_ENDPOINT"

  let get_url_traces_from_env =
    make_get_from_env "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"

  let get_url_metrics_from_env =
    make_get_from_env "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT"

  let get_url_logs_from_env =
    make_get_from_env "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"

  let remove_trailing_slash url =
    if url <> "" && String.get url (String.length url - 1) = '/' then
      String.sub url 0 (String.length url - 1)
    else
      url

  let parse_headers s =
    let parse_header s =
      match String.split_on_char '=' s with
      | [ key; value ] -> key, value
      | _ -> failwith "Unexpected format for header"
    in
    String.split_on_char ',' s |> List.map parse_header

  let get_headers_from_env env_name =
    try parse_headers (Sys.getenv env_name) with _ -> []

  let get_general_headers_from_env () =
    try parse_headers (Sys.getenv "OTEL_EXPORTER_OTLP_HEADERS") with _ -> []
end

module Env () : ENV = struct
  let merge_headers base specific =
    (* Signal-specific headers override generic ones *)
    let specific_keys = List.map fst specific in
    let filtered_base =
      List.filter (fun (k, _) -> not (List.mem k specific_keys)) base
    in
    List.rev_append specific filtered_base

  let make k ?(debug = get_debug_from_env ())
      ?(log_level = get_log_level_from_env ())
      ?(sdk_disabled = get_sdk_disabled_from_env ()) ?url ?url_traces
      ?url_metrics ?url_logs ?batch_traces ?batch_metrics ?batch_logs
      ?(batch_timeout_ms = 2_000) ?traces ?metrics ?logs
      ?(headers = get_general_headers_from_env ()) ?headers_traces
      ?headers_metrics ?headers_logs
      ?(protocol = get_protocol_from_env "OTEL_EXPORTER_OTLP_PROTOCOL")
      ?(timeout_ms = get_timeout_from_env "OTEL_EXPORTER_OTLP_TIMEOUT" 10_000)
      ?timeout_traces_ms ?timeout_metrics_ms ?timeout_logs_ms
      ?(self_trace = false) ?(self_metrics = false) ?http_concurrency_level
      ?(retry_max_attempts = 3) ?(retry_initial_delay_ms = 100.)
      ?(retry_max_delay_ms = 5000.) ?(retry_backoff_multiplier = 2.0)
      ?(sampler = Opentelemetry.Trace_sampler.of_env ()) =
    let sampler = Some sampler in
    let batch_timeout_ = Mtime.Span.(batch_timeout_ms * ms) in
    let traces =
      match traces with
      | Some t -> t
      | None ->
        let batch =
          match batch_traces with
          | Some b -> b
          | None -> get_timeout_from_env "OTEL_BSP_MAX_EXPORT_BATCH_SIZE" 400
        in
        Opentelemetry.Provider_config.make ~batch ~timeout:batch_timeout_ ()
    in
    let metrics =
      match metrics with
      | Some m -> m
      | None ->
        let batch =
          match batch_metrics with
          | Some b -> b
          | None -> get_timeout_from_env "OTEL_METRIC_EXPORT_INTERVAL" 200
        in
        Opentelemetry.Provider_config.make ~batch ~timeout:batch_timeout_ ()
    in
    let logs =
      match logs with
      | Some l -> l
      | None ->
        let batch = Option.value batch_logs ~default:400 in
        Opentelemetry.Provider_config.make ~batch ~timeout:batch_timeout_ ()
    in

    let url_traces, url_metrics, url_logs =
      let base_url =
        let base_url =
          match get_url_from_env () with
          | None -> Option.value url ~default:default_url
          | Some url -> remove_trailing_slash url
        in
        remove_trailing_slash base_url
      in
      let url_traces =
        match get_url_traces_from_env () with
        | None -> Option.value url_traces ~default:(base_url ^ "/v1/traces")
        | Some url -> url
      in
      let url_metrics =
        match get_url_metrics_from_env () with
        | None -> Option.value url_metrics ~default:(base_url ^ "/v1/metrics")
        | Some url -> url
      in
      let url_logs =
        match get_url_logs_from_env () with
        | None -> Option.value url_logs ~default:(base_url ^ "/v1/logs")
        | Some url -> url
      in
      url_traces, url_metrics, url_logs
    in

    (* Get per-signal headers from env vars *)
    let env_headers_traces =
      get_headers_from_env "OTEL_EXPORTER_OTLP_TRACES_HEADERS"
    in
    let env_headers_metrics =
      get_headers_from_env "OTEL_EXPORTER_OTLP_METRICS_HEADERS"
    in
    let env_headers_logs =
      get_headers_from_env "OTEL_EXPORTER_OTLP_LOGS_HEADERS"
    in

    (* Merge with provided headers, env-specific takes precedence *)
    let headers_traces =
      match headers_traces with
      | Some h -> h
      | None -> merge_headers headers env_headers_traces
    in
    let headers_metrics =
      match headers_metrics with
      | Some h -> h
      | None -> merge_headers headers env_headers_metrics
    in
    let headers_logs =
      match headers_logs with
      | Some h -> h
      | None -> merge_headers headers env_headers_logs
    in

    (* Get per-signal timeouts from env vars with fallback to general timeout *)
    let timeout_traces_ms =
      match timeout_traces_ms with
      | Some t -> t
      | None ->
        get_timeout_from_env "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT" timeout_ms
    in
    let timeout_metrics_ms =
      match timeout_metrics_ms with
      | Some t -> t
      | None ->
        get_timeout_from_env "OTEL_EXPORTER_OTLP_METRICS_TIMEOUT" timeout_ms
    in
    let timeout_logs_ms =
      match timeout_logs_ms with
      | Some t -> t
      | None ->
        get_timeout_from_env "OTEL_EXPORTER_OTLP_LOGS_TIMEOUT" timeout_ms
    in

    k
      {
        debug;
        log_level;
        sdk_disabled;
        url_traces;
        url_metrics;
        url_logs;
        headers;
        headers_traces;
        headers_metrics;
        headers_logs;
        protocol;
        timeout_ms;
        timeout_traces_ms;
        timeout_metrics_ms;
        timeout_logs_ms;
        traces;
        metrics;
        logs;
        self_trace;
        self_metrics;
        http_concurrency_level;
        retry_max_attempts;
        retry_initial_delay_ms;
        retry_max_delay_ms;
        retry_backoff_multiplier;
        sampler;
        _rest = ();
      }
end
