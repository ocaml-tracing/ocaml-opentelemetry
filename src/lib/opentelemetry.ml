(** Main Opentelemetry API for libraries and user code. *)

module Core = Opentelemetry_core
(** Core types and definitions *)

module Interval_limiter = Interval_limiter
(** Utility to limit the frequency of some event
    @since NEXT_RELEASE *)

(** {2 Wire format} *)

module Proto = Opentelemetry_proto
(** Protobuf types.

    This is mostly useful internally. Users should not need to touch it. *)

(** {2 Time} *)

module Clock = Clock
module Timestamp_ns = Timestamp_ns

(** {2 Export signals to some external collector.} *)

module Emitter = Opentelemetry_emitter.Emitter

module Exporter = struct
  include Exporter

  (** Get a tracer from this exporter.
      @since NEXT_RELEASE *)
  let get_tracer (self : t) : Tracer.t = Tracer.of_exporter self

  (** Get a meter from this exporter.
      @since NEXT_RELEASE *)
  let get_meter (self : t) : Meter.t = Meter.of_exporter self

  (** Get a logger from this exporter.
      @since NEXT_RELEASE *)
  let get_logger (self : t) : Logger.t = Logger.of_exporter self
end

module Sdk = struct
  include Sdk

  (** Get a tracer forwarding to the current main exporter.
      @since NEXT_RELEASE *)
  let get_tracer ?name ?version ?attrs ?__MODULE__ () =
    Trace_provider.get_tracer ?name ?version ?attrs ?__MODULE__ ()

  (** Get a meter forwarding to the current main exporter.
      @since NEXT_RELEASE *)
  let get_meter ?name ?version ?attrs ?__MODULE__ () =
    Meter_provider.get_meter ?name ?version ?attrs ?__MODULE__ ()

  (** Get a logger forwarding to the current main exporter.
      @since NEXT_RELEASE *)
  let get_logger ?name ?version ?attrs ?__MODULE__ () =
    Log_provider.get_logger ?name ?version ?attrs ?__MODULE__ ()
end

module Main_exporter = Sdk [@@deprecated "use Sdk instead"]

module Collector = struct
  include Exporter
  include Sdk
end
[@@deprecated "Use 'Exporter' instead"]

module Dynamic_enricher = Dynamic_enricher
module Trace_provider = Trace_provider
module Meter_provider = Meter_provider
module Log_provider = Log_provider

(** {2 Identifiers} *)

module Trace_id = Trace_id

let k_trace_id = Trace_id.k_trace_id

module Span_id = Span_id
module Span_ctx = Span_ctx

let k_ambient = Span_ctx.k_ambient

(** {2 Attributes and conventions} *)

module Conventions = Conventions
module Value = Value
module Key_value = Key_value

type value = Value.t
(** A value in a key/value attribute *)

type key_value = Key_value.t

(** {2 Global settings} *)

module Globals = Globals

(** {2 Traces and Spans} *)

module Event = Event
module Span_link = Span_link
module Span_status = Span_status
module Span_kind = Span_kind

(** {2 Traces} *)

module Span = Span
module Ambient_span = Ambient_span

module Tracer = struct
  include Tracer

  let default = Trace_provider.default_tracer

  let with_thunk_and_finally = Trace_provider.with_thunk_and_finally

  let with_ = Trace_provider.with_
end

module Trace = Tracer [@@deprecated "use Tracer instead"]

(** {2 Metrics} *)

module Metrics = Metrics
module Instrument = Instrument

module Meter = struct
  include Meter

  let default = Meter_provider.default_meter

  let add_to_exporter = Meter_provider.add_to_exporter

  let add_to_main_exporter = Meter_provider.add_to_main_exporter
end

(** {2 Logs} *)

module Log_record = Log_record

module Logger = struct
  include Logger

  let default = Log_provider.default_logger

  let log = Log_provider.log

  let logf = Log_provider.logf
end

module Logs = Logger [@@deprecated "use Logger"]

(** {2 Utils} *)

module Any_signal = Any_signal
module Any_signal_l = Any_signal_l
module Trace_context = Trace_context
module Gc_metrics = Gc_metrics

module Aswitch = Aswitch
(** @since NEXT_RELEASE *)

module Alist = Alist
(** Atomic list, for internal usage
    @since 0.7 *)

(* *)

module GC_metrics = Gc_metrics
[@@deprecated "use Gc_metrics (beware capitalization)"]
