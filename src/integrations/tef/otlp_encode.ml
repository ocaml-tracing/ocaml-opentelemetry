(** Pure grouping + OTLP wire encoding of a {!Convert.bundle}, using only the
    [opentelemetry] proto modules (no client/exporter dependency).

    Produces the [Export*ServiceRequest] payloads that an OTLP/HTTP collector
    expects on [/v1/traces] and [/v1/metrics], either as protobuf bytes or as
    JSON. *)

module Proto = Opentelemetry.Proto

let resource_of_bundle (b : Convert.bundle) : Proto.Resource.resource =
  let attributes =
    Opentelemetry.Globals.mk_attributes ?service_name:b.Convert.service_name ()
  in
  Proto.Resource.make_resource ~attributes ()

let resource_spans (b : Convert.bundle) : Proto.Trace.resource_spans list =
  match b.Convert.spans with
  | [] -> []
  | spans ->
    let scope_spans =
      Proto.Trace.make_scope_spans
        ~scope:Opentelemetry.Globals.instrumentation_library ~spans ()
    in
    [
      Proto.Trace.make_resource_spans ~resource:(resource_of_bundle b)
        ~scope_spans:[ scope_spans ] ();
    ]

let resource_metrics (b : Convert.bundle) : Proto.Metrics.resource_metrics list
    =
  match b.Convert.metrics with
  | [] -> []
  | metrics ->
    let scope_metrics =
      Proto.Metrics.make_scope_metrics
        ~scope:Opentelemetry.Globals.instrumentation_library ~metrics ()
    in
    [
      Proto.Metrics.make_resource_metrics ~resource:(resource_of_bundle b)
        ~scope_metrics:[ scope_metrics ] ();
    ]

let to_pb enc x : string =
  let e = Pbrt.Encoder.create () in
  enc x e;
  Pbrt.Encoder.to_string e

(** Protobuf-encoded [ExportTraceServiceRequest]; [""] when there are no spans.
*)
let traces_protobuf (b : Convert.bundle) : string =
  match resource_spans b with
  | [] -> ""
  | rs ->
    let req =
      Proto.Trace_service.make_export_trace_service_request ~resource_spans:rs
        ()
    in
    to_pb Proto.Trace_service.encode_pb_export_trace_service_request req

(** Protobuf-encoded [ExportMetricsServiceRequest]; [""] when there are no
    metrics. *)
let metrics_protobuf (b : Convert.bundle) : string =
  match resource_metrics b with
  | [] -> ""
  | rm ->
    let req =
      Proto.Metrics_service.make_export_metrics_service_request
        ~resource_metrics:rm ()
    in
    to_pb Proto.Metrics_service.encode_pb_export_metrics_service_request req

(** JSON [ExportTraceServiceRequest]; [`Null] when there are no spans. *)
let traces_json_value (b : Convert.bundle) : Yojson.Basic.t =
  match resource_spans b with
  | [] -> `Null
  | rs ->
    let req =
      Proto.Trace_service.make_export_trace_service_request ~resource_spans:rs
        ()
    in
    Proto.Trace_service.encode_json_export_trace_service_request req

(** JSON [ExportMetricsServiceRequest]; [`Null] when there are no metrics. *)
let metrics_json_value (b : Convert.bundle) : Yojson.Basic.t =
  match resource_metrics b with
  | [] -> `Null
  | rm ->
    let req =
      Proto.Metrics_service.make_export_metrics_service_request
        ~resource_metrics:rm ()
    in
    Proto.Metrics_service.encode_json_export_metrics_service_request req

let traces_json (b : Convert.bundle) : string =
  match traces_json_value b with
  | `Null -> ""
  | j -> Yojson.Basic.to_string j

let metrics_json (b : Convert.bundle) : string =
  match metrics_json_value b with
  | `Null -> ""
  | j -> Yojson.Basic.to_string j
