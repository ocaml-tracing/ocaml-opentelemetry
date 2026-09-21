(** Error that can occur during export *)

type attempt_descr = string

type t =
  [ `Status of int * Opentelemetry.Proto.Status.status * attempt_descr
  | `Failure of string
  | `Sysbreak
  ]

open struct
  let str_to_hex (s : string) : string =
    Opentelemetry_util.Util_bytes_.bytes_to_hex (Bytes.unsafe_of_string s)

  (** Can we just show the body of a HTTP error? *)
  let is_safe_for_direct_display s : bool =
    let ok = ref true in
    let has_visible = ref false in
    let i = ref 0 in
    while !i < String.length s && !ok do
      let c = String.unsafe_get s !i in
      if c = '\n' || c = '\t' || c = ' ' then
        ()
      else (
        let c = Char.code c in
        if c >= 0x21 && c <= 0x7e then
          has_visible := true
        else
          ok := false
      );

      incr i
    done;
    !ok && !has_visible

  let failuref fmt = Printf.ksprintf (fun s -> `Failure s) fmt
end

(** Report the error on stderr. *)
let report_err ~level:(provided_level : [ `Debug | `Warning | `Auto ]) (err : t)
    : unit =
  let compute_level lvl =
    match provided_level with
    | `Debug -> Opentelemetry.Self_debug.Debug
    | `Warning -> Opentelemetry.Self_debug.Warning
    | `Auto -> lvl
  in
  match err with
  | `Sysbreak ->
    Opentelemetry.Self_debug.log (compute_level Info) (fun () ->
        "opentelemetry: ctrl-c captured, stopping")
  | `Failure msg ->
    Opentelemetry.Self_debug.log (compute_level Error) (fun () ->
        Printf.sprintf "opentelemetry: export failed\n%s" msg)
  | `Status
      ( code,
        {
          Opentelemetry.Proto.Status.code = scode;
          message;
          details;
          _presence = _;
        },
        descr ) ->
    Opentelemetry.Self_debug.log (compute_level Error) (fun () ->
        let pp_details out l =
          List.iter
            (fun s -> Format.fprintf out "%S;@ " (Bytes.unsafe_to_string s))
            l
        in

        Format.asprintf
          "@[<2>opentelemetry: export failed with@ http code=%d@ attempt: %s@ \
           status {@[code=%ld;@ message=%S;@ details=[@[%a@]]@]}@]"
          code descr scode
          (Bytes.unsafe_to_string message)
          pp_details details)

let decode_invalid_http_response ~attempt_descr ~code ~url (body : string) : t =
  try
    let dec = Pbrt.Decoder.of_string body in
    let status = Opentelemetry.Proto.Status.decode_pb_status dec in
    `Status (code, status, attempt_descr)
  with e ->
    let bt = Printexc.get_backtrace () in
    if is_safe_for_direct_display body then
      failuref
        "http server at %s returned code %d\n\
         (export: %s);\n\
         HTTP response body:\n\
         %s"
        url code attempt_descr body
    else
      failuref
        "http server at %s returned code %d\n\
         (export: %s);\n\
         trying to decode the body as protobuf failed:\n\
         %s\n\
         raw HTTP body (hex): %s\n\
         %s"
        url code attempt_descr (Printexc.to_string e) (str_to_hex body) bt
