(** Logs.

    See
    {{:https://opentelemetry.io/docs/reference/specification/overview/#log-signal}
     the spec} *)

open Common_
open Proto.Logs

type t = Proto.Logs.log_record

(** Severity level of a log event *)
type severity = Proto.Logs.severity_number =
  | Severity_number_unspecified
  | Severity_number_trace
  | Severity_number_trace2
  | Severity_number_trace3
  | Severity_number_trace4
  | Severity_number_debug
  | Severity_number_debug2
  | Severity_number_debug3
  | Severity_number_debug4
  | Severity_number_info
  | Severity_number_info2
  | Severity_number_info3
  | Severity_number_info4
  | Severity_number_warn
  | Severity_number_warn2
  | Severity_number_warn3
  | Severity_number_warn4
  | Severity_number_error
  | Severity_number_error2
  | Severity_number_error3
  | Severity_number_error4
  | Severity_number_fatal
  | Severity_number_fatal2
  | Severity_number_fatal3
  | Severity_number_fatal4

let pp_severity = pp_severity_number

type flags = Proto.Logs.log_record_flags =
  | Log_record_flags_do_not_use
  | Log_record_flags_trace_flags_mask

let pp_flags = Proto.Logs.pp_log_record_flags

let pp = Proto.Logs.pp_log_record

(** Make a single log entry. *)
let make ?time ?severity ?log_level ?flags ?trace_id ?span_id ?(attrs = [])
    ~(observed_time_unix_nano : Timestamp_ns.t) (body : Value.t) : t =
  let time_unix_nano =
    match time with
    | None -> observed_time_unix_nano
    | Some t -> t
  in
  let trace_id = Option.map Trace_id.to_bytes trace_id in
  let span_id = Option.map Span_id.to_bytes span_id in
  let body = Value.conv body in
  let attributes = List.map Key_value.conv attrs in
  make_log_record ~time_unix_nano ~observed_time_unix_nano
    ?severity_number:severity ?severity_text:log_level ?flags ?trace_id ?span_id
    ~attributes ?body ()

(** Make a log entry whose body is a string *)
let make_str ?time ?severity ?log_level ?flags ?trace_id ?span_id ?attrs
    ~observed_time_unix_nano (body : string) : t =
  make ?time ~observed_time_unix_nano ?severity ?log_level ?flags ?trace_id
    ?span_id ?attrs (`String body)

(** Make a log entry with format *)
let make_strf ?time ?severity ?log_level ?flags ?trace_id ?span_id ?attrs
    ~observed_time_unix_nano fmt =
  Format.kasprintf
    (fun bod ->
      make_str ?time ~observed_time_unix_nano ?severity ?log_level ?flags
        ?trace_id ?span_id ?attrs bod)
    fmt

let add_attrs (self : t) (attrs : Key_value.t list) : unit =
  let attrs = List.map Key_value.conv attrs in
  Proto.Logs.log_record_set_attributes self (attrs @ self.attributes)
