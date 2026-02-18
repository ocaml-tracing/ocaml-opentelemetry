module Otel = Opentelemetry

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* This module is for sending logs from the Logs library
   (https://github.com/dbuenzli/logs) via OTel. It is NOT a general logging
   library (See Logs for that).
*)
(*****************************************************************************)
(* Levels *)
(*****************************************************************************)
(* Convert log level to Otel severity *)
let log_level_to_severity (level : Logs.level) : Otel.Logs.severity =
  match level with
  | Logs.App -> Otel.Logs.Severity_number_info (* like info, but less severe  *)
  | Logs.Info -> Otel.Logs.Severity_number_info2
  | Logs.Error -> Otel.Logs.Severity_number_error
  | Logs.Warning -> Otel.Logs.Severity_number_warn
  | Logs.Debug -> Otel.Logs.Severity_number_debug

(*****************************************************************************)
(* Logs Util *)
(*****************************************************************************)

let emit_telemetry_tag =
  Logs.Tag.def ~doc:"Whether or not to emit this log via telemetry"
    "emit_telemetry" Format.pp_print_bool

let emit_telemetry do_emit = Logs.Tag.(empty |> add emit_telemetry_tag do_emit)

(*****************************************************************************)
(* Logging *)
(*****************************************************************************)

(* Log a message to otel with some attrs *)
let log ?service_name ?(attrs = []) ?(scope = Otel.Scope.get_ambient_scope ())
    ~level msg =
  let log_level = Logs.level_to_string (Some level) in
  let span_id =
    Option.map (fun (scope : Otel.Scope.t) -> scope.span_id) scope
  in
  let trace_id =
    Option.map (fun (scope : Otel.Scope.t) -> scope.trace_id) scope
  in
  let severity = log_level_to_severity level in
  let log = Otel.Logs.make_str ~severity ~log_level ?trace_id ?span_id msg in
  (* Noop if no backend is set *)
  Otel.Logs.emit ?service_name ~attrs [ log ]

let otel_reporter ?service_name ?(attributes = []) () : Logs.reporter =
  let report src level ~over k msgf =
    msgf (fun ?header ?(tags : Logs.Tag.set option) fmt ->
        let k _ =
          over ();
          k ()
        in
        Format.kasprintf
          (fun msg ->
            let tags = Option.value ~default:Logs.Tag.empty tags in
            let attrs =
              let tags =
                Logs.Tag.fold
                  (fun (Logs.Tag.(V (d, v)) : Logs.Tag.t) acc ->
                    let name = Logs.Tag.name d in
                    (* Is there a better way to compare tags? structural equality does not work *)
                    if String.equal name (Logs.Tag.name emit_telemetry_tag) then
                      (* Don't include the emit_telemetry_tag in the attributes *)
                      acc
                    else (
                      let value =
                        let value_printer = Logs.Tag.printer d in
                        (* Also the default for Format.asprintf *)
                        let buffer = Buffer.create 512 in
                        let formatter = Format.formatter_of_buffer buffer in
                        value_printer formatter v;
                        Buffer.contents buffer
                      in
                      let s = name, `String value in
                      s :: acc
                    ))
                  tags []
              in
              let header =
                match header with
                | None -> []
                | Some h -> [ "header", `String h ]
              in
              let src_str = Logs.Src.name src in
              header @ [ "src", `String src_str ] @ tags @ attributes
            in
            let do_emit =
              Option.value ~default:true (Logs.Tag.find emit_telemetry_tag tags)
            in
            if do_emit then log ?service_name ~attrs ~level msg;
            k ())
          fmt)
  in
  { Logs.report }

let attach_otel_reporter ?service_name ?attributes reporter =
  (* Copied directly from the Logs.mli docs. Just calls a bunch of reporters in a
   row *)
  let combine r1 r2 =
    let report src level ~over k msgf =
      let v = r1.Logs.report src level ~over:(fun () -> ()) k msgf in
      r2.Logs.report src level ~over (fun () -> v) msgf
    in
    { Logs.report }
  in
  let otel_reporter = otel_reporter ?service_name ?attributes () in
  combine reporter otel_reporter
