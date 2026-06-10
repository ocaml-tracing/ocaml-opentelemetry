(* Implementation selected when [curly] is available (see dune). *)

type protocol =
  | Protobuf
  | Json

let available = true

let default_endpoint () =
  match Sys.getenv_opt "OTEL_EXPORTER_OTLP_ENDPOINT" with
  | Some u -> u
  | None -> "http://localhost:4318"

let content_type = function
  | Protobuf -> "application/x-protobuf"
  | Json -> "application/json"

let strip_trailing_slash s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '/' then
    String.sub s 0 (n - 1)
  else
    s

let post_one ~endpoint ~protocol ~path ~body : (unit, string) result =
  if body = "" then
    Ok () (* nothing of this signal kind to send *)
  else (
    let url = endpoint ^ path in
    let ct = content_type protocol in
    let headers = [ "Content-Type", ct; "Accept", ct ] in
    match Curly.post ~headers ~body url with
    | Ok { Curly.Response.code; body = resp; _ } ->
      if code >= 200 && code < 300 then
        Ok ()
      else
        Error (Printf.sprintf "POST %s -> HTTP %d: %s" url code resp)
    | Error e -> Error (Format.asprintf "POST %s -> %a" url Curly.Error.pp e)
  )

let send ?endpoint ?(protocol = Protobuf) (b : Convert.bundle) :
    (unit, string) result =
  let endpoint =
    strip_trailing_slash
      (match endpoint with
      | Some e -> e
      | None -> default_endpoint ())
  in
  let traces_body, metrics_body =
    match protocol with
    | Protobuf -> Otlp_encode.traces_protobuf b, Otlp_encode.metrics_protobuf b
    | Json -> Otlp_encode.traces_json b, Otlp_encode.metrics_json b
  in
  let ( let* ) = Result.bind in
  let* () = post_one ~endpoint ~protocol ~path:"/v1/traces" ~body:traces_body in
  let* () =
    post_one ~endpoint ~protocol ~path:"/v1/metrics" ~body:metrics_body
  in
  Ok ()
