(** otel-of-tef: read a TEF trace, convert it to OpenTelemetry spans + metrics,
    and either dump the OTLP payload (default) or send it to a collector
    ([--send]). A thin CLI over the [opentelemetry.import-tef] library. *)

module Imp = Opentelemetry_import_tef
module Tef_event = Imp.Tef_event
module Convert = Imp.Convert
module Otlp_encode = Imp.Otlp_encode
module Curl_export = Imp.Curl_export

let read_all : in_channel -> string = In_channel.input_all

let read_input = function
  | None -> read_all stdin
  | Some file ->
    let ic = open_in_bin file in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> read_all ic)

let to_hex (s : string) : string =
  let b = Buffer.create (String.length s * 2) in
  String.iter
    (fun c -> Buffer.add_string b (Printf.sprintf "%02x" (Char.code c)))
    s;
  Buffer.contents b

let () =
  let input = ref None in
  let jsonl = ref false in
  let send = ref false in
  let endpoint = ref None in
  let service = ref None in
  let base_time = ref 0L in
  let dump_fmt = ref "json" in
  let protocol = ref "protobuf" in
  let spec =
    [
      ( "--jsonl",
        Arg.Set jsonl,
        " parse newline-delimited JSON instead of a JSON array" );
      ( "--send",
        Arg.Set send,
        " send the bundle to a collector instead of dumping it" );
      ( "--endpoint",
        Arg.String (fun s -> endpoint := Some s),
        "URL collector base URL (implies --send; default \
         OTEL_EXPORTER_OTLP_ENDPOINT or http://localhost:4318)" );
      ( "--service-name",
        Arg.String (fun s -> service := Some s),
        "NAME set the service.name resource attribute" );
      ( "--base-time",
        Arg.String (fun s -> base_time := Int64.of_string s),
        "NS nanosecond offset added to every timestamp (for monotonic-clock \
         traces)" );
      ( "--dump-format",
        Arg.Symbol ([ "json"; "pretty"; "protobuf-hex" ], fun s -> dump_fmt := s),
        " output format when dumping (default: json)" );
      ( "--protocol",
        Arg.Symbol ([ "protobuf"; "json" ], fun s -> protocol := s),
        " wire protocol when sending (default: protobuf)" );
    ]
  in
  let usage =
    "otel-of-tef [options] [FILE]\n\n\
     Convert a TEF trace (default: stdin) to OTEL signals.\n\
     By default prints the OTLP payload; use --send to push to a collector.\n"
  in
  Arg.parse (Arg.align spec) (fun f -> input := Some f) usage;

  let data = read_input !input in
  let events =
    if !jsonl then
      Tef_event.parse_jsonl data
    else
      Tef_event.parse_string data
  in
  let bundle =
    Convert.of_events ?service_name:!service ~base_ns:!base_time events
  in

  if !send || !endpoint <> None then (
    if not Curl_export.available then (
      prerr_endline
        "otel-of-tef: --send requires the `curly` library, which was not \
         available at build time.";
      exit 1
    );
    let protocol =
      match !protocol with
      | "json" -> Curl_export.Json
      | _ -> Curl_export.Protobuf
    in
    match Curl_export.send ?endpoint:!endpoint ~protocol bundle with
    | Ok () ->
      Printf.eprintf "otel-of-tef: sent %d spans, %d metrics\n"
        (List.length bundle.Convert.spans)
        (List.length bundle.Convert.metrics)
    | Error e ->
      prerr_endline ("otel-of-tef: " ^ e);
      exit 1
  ) else (
    match !dump_fmt with
    | "protobuf-hex" ->
      let t = Otlp_encode.traces_protobuf bundle in
      let m = Otlp_encode.metrics_protobuf bundle in
      if t <> "" then Printf.printf "traces: %s\n" (to_hex t);
      if m <> "" then Printf.printf "metrics: %s\n" (to_hex m)
    | "pretty" | "json" ->
      let combined : Yojson.Basic.t =
        `Assoc
          [
            "traces", Otlp_encode.traces_json_value bundle;
            "metrics", Otlp_encode.metrics_json_value bundle;
          ]
      in
      let s =
        if !dump_fmt = "pretty" then
          Yojson.Basic.pretty_to_string combined
        else
          Yojson.Basic.to_string combined
      in
      print_endline s
    | _ -> assert false
  )
