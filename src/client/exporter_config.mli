(** Constructing and managing the configuration common to many (most?)
    HTTP-based clients.

    This is extended and reused by concrete client implementations that exports
    signals over HTTP, depending on their needs. *)

type protocol =
  | Http_protobuf
  | Http_json

type log_level = Opentelemetry.Self_debug.level option
(** [None] disables internal diagnostic logging; [Some level] enables it at that
    level and above. Maps to [OTEL_LOG_LEVEL] env var. *)

type rest
(** opaque type to force using {!make} while allowing record updates *)

type t = {
  debug: bool; [@alert deprecated "Use log_level instead"]
      (** @deprecated Use {!log_level} instead. Debug the client itself? *)
  log_level: log_level;
      (** Log level for internal diagnostics. Read from OTEL_LOG_LEVEL or falls
          back to OTEL_OCAML_DEBUG for compatibility. *)
  sdk_disabled: bool;
      (** If true, the SDK is completely disabled and no-ops. Read from
          OTEL_SDK_DISABLED. Default false. *)
  url_traces: string;  (** Url to send traces/spans *)
  url_metrics: string;  (** Url to send metrics*)
  url_logs: string;  (** Url to send logs *)
  headers: (string * string) list;
      (** Global API headers sent to all endpoints. Default is none or
          "OTEL_EXPORTER_OTLP_HEADERS" if set. Signal-specific headers can
          override these. *)
  headers_traces: (string * string) list;
      (** Headers for traces endpoint. Merges OTEL_EXPORTER_OTLP_HEADERS with
          OTEL_EXPORTER_OTLP_TRACES_HEADERS (signal-specific takes precedence).
      *)
  headers_metrics: (string * string) list;
      (** Headers for metrics endpoint. Merges OTEL_EXPORTER_OTLP_HEADERS with
          OTEL_EXPORTER_OTLP_METRICS_HEADERS (signal-specific takes precedence).
      *)
  headers_logs: (string * string) list;
      (** Headers for logs endpoint. Merges OTEL_EXPORTER_OTLP_HEADERS with
          OTEL_EXPORTER_OTLP_LOGS_HEADERS (signal-specific takes precedence). *)
  protocol: protocol;
      (** Wire protocol to use. Read from OTEL_EXPORTER_OTLP_PROTOCOL. Default
          Http_protobuf. *)
  timeout_ms: int;
      (** General timeout in milliseconds for exporter operations. Read from
          OTEL_EXPORTER_OTLP_TIMEOUT. Default 10_000. *)
  timeout_traces_ms: int;
      (** Timeout for trace exports. Read from
          OTEL_EXPORTER_OTLP_TRACES_TIMEOUT, falls back to timeout_ms. *)
  timeout_metrics_ms: int;
      (** Timeout for metric exports. Read from
          OTEL_EXPORTER_OTLP_METRICS_TIMEOUT, falls back to timeout_ms. *)
  timeout_logs_ms: int;
      (** Timeout for log exports. Read from OTEL_EXPORTER_OTLP_LOGS_TIMEOUT,
          falls back to timeout_ms. *)
  traces: Opentelemetry.Provider_config.t;
      (** Per-provider batching config for traces. Default: batch=400,
          timeout=2s. The batch size is read from OTEL_BSP_MAX_EXPORT_BATCH_SIZE
          if set. *)
  metrics: Opentelemetry.Provider_config.t;
      (** Per-provider batching config for metrics. Default: batch=200,
          timeout=2s. The batch size is read from OTEL_METRIC_EXPORT_INTERVAL if
          set. *)
  logs: Opentelemetry.Provider_config.t;
      (** Per-provider batching config for logs. Default: batch=400, timeout=2s.
      *)
  self_trace: bool;
      (** If true, the OTEL library will perform some self-instrumentation.
          Default [false].
          @since 0.7 *)
  self_metrics: bool;
      (** If true, the OTEL library will regularly emit metrics about itself.
          Default [false].
          @since 0.90 *)
  http_concurrency_level: int option;
      (** How many HTTP requests can be done simultaneously (at most)? This can
          be used to represent the size of a pool of workers where each worker
          gets a batch to send, send it, and repeats.
          @since 0.90 *)
  retry_max_attempts: int;
      (** Maximum number of retry attempts for failed exports. 0 means no retry,
          1 means one retry after initial failure. Default 3. *)
  retry_initial_delay_ms: float;
      (** Initial delay in milliseconds before first retry. Default 100ms. *)
  retry_max_delay_ms: float;
      (** Maximum delay in milliseconds between retries. Default 5000ms. *)
  retry_backoff_multiplier: float;
      (** Multiplier for exponential backoff. Default 2.0. *)
  _rest: rest;
}
(** Configuration.

    To build one, use {!make} below. This might be extended with more fields in
    the future. *)

val default_url : string
(** The default base URL for the config. *)

val pp : Format.formatter -> t -> unit

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
  'k
(** A function that gathers all the values needed to construct a {!t}, and
    produces a ['k]. ['k] is typically a continuation used to construct a
    configuration that includes a {!t}.

    @param url
      base url used to construct per-signal urls. Per-signal url options take
      precedence over this base url. If not provided, this defaults to
      "OTEL_EXPORTER_OTLP_ENDPOINT" if set, or if not {!default_url}.

    Example of constructed per-signal urls with the base url
    http://localhost:4318
    - Traces: http://localhost:4318/v1/traces
    - Metrics: http://localhost:4318/v1/metrics
    - Logs: http://localhost:4318/v1/logs

    Use per-signal url options if different urls are needed for each signal
    type.

    @param url_traces
      url to send traces, or "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" if set. The
      url is used as-is without any modification.

    @param url_metrics
      url to send metrics, or "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" if set. The
      url is used as-is without any modification.

    @param url_logs
      url to send logs, or "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT" if set. The url is
      used as-is without any modification. *)

(** Construct, inspect, and update {!t} configurations, drawing defaults from
    the environment *)
module type ENV = sig
  val make : (t -> 'a) -> 'a make
  (** [make f] is a {!type:make} function that will give [f] a safely
      constructed {!t}.

      Typically this is used to extend the constructor for {!t} with new
      optional arguments.

      E.g., we can construct a configuration that includes a {!t} alongside a
      more specific field like so:

      {[
        type extended_config = {
          new_field: string;
          common: t;
        }

        let make : (new_field:string -> unit -> extended_config) make =
          Env.make (fun common ~new_field () -> { new_field; common })

        let _example : extended_config =
          make ~new_field:"foo" ~url_traces:"foo/bar" ~debug:true ()
      ]}

      As a special case, we can get the simple constructor function for {!t}
      with [Env.make (fun common () -> common)] *)
end

(** A generative functor that produces a state-space that can read configuration
    values from the environment, provide stateful configuration setting and
    accessing operations, and a way to make a new {!t} configuration record *)
module Env : functor () -> ENV
