module Otel = Opentelemetry
module Otel_lwt = Opentelemetry_lwt
open Cohttp

open struct
  let attrs_of_response (res : Response.t) =
    let code = Response.status res in
    let code = Code.code_of_status code in
    [ "http.status_code", `Int code ]
end

module Server : sig
  val trace :
    ?tracer:Otel.Tracer.t ->
    ?attrs:Otel.Span.key_value list ->
    ('conn -> Request.t -> 'body -> (Response.t * 'body) Lwt.t) ->
    'conn ->
    Request.t ->
    'body ->
    (Response.t * 'body) Lwt.t
  (** Trace requests to a Cohttp server.

      Use it like this:

      {[
        let my_server callback =
          let callback_traced =
            Opentelemetry_cohttp_lwt.Server.trace ~service_name:"my-service"
              (fun _scope -> callback)
          in
          Cohttp_lwt_unix.Server.create
            ~mode:(`TCP (`Port 8080))
            (Server.make () ~callback:callback_traced)
      ]} *)

  val with_ :
    ?tracer:Otel.Tracer.t ->
    ?trace_state:string ->
    ?attrs:Otel.Span.key_value list ->
    ?kind:Otel.Span.kind ->
    ?links:Otel.Span_link.t list ->
    string ->
    Request.t ->
    (Request.t -> 'a Lwt.t) ->
    'a Lwt.t
  (** Trace a new internal span.

      Identical to [Opentelemetry_lwt.Trace.with_], but fetches/stores the trace
      scope in the [x-ocaml-otel-traceparent] header in the request for
      convenience. *)

  val get_trace_context :
    ?from:[ `Internal | `External ] -> Request.t -> Otel.Span.t option
  (** Get the tracing scope from the custom [x-ocaml-otel-traceparent] header
      added by [trace] and [with_]. *)

  val set_trace_context : Otel.Span.t -> Request.t -> Request.t
  (** Set the tracing scope in the custom [x-ocaml-otel-traceparent] header used
      by [trace] and [with_]. *)

  val remove_trace_context : Request.t -> Request.t
  (** Strip the custom [x-ocaml-otel-traceparent] header added by [trace] and
      [with_]. *)
end = struct
  let attrs_of_request (req : Request.t) =
    let meth = req |> Request.meth |> Code.string_of_method in
    let referer = Header.get (Request.headers req) "referer" in
    let host = Header.get (Request.headers req) "host" in
    let ua = Header.get (Request.headers req) "user-agent" in
    let uri = Request.uri req in
    List.concat
      [
        [ "http.method", `String meth ];
        (match host with
        | None -> []
        | Some h -> [ "http.host", `String h ]);
        [ "http.url", `String (Uri.to_string uri) ];
        (match ua with
        | None -> []
        | Some ua -> [ "http.user_agent", `String ua ]);
        (match referer with
        | None -> []
        | Some r -> [ "http.request.header.referer", `String r ]);
      ]

  let header_x_ocaml_otel_traceparent = "x-ocaml-otel-traceparent"

  let set_trace_context (span : Otel.Span.t) req =
    let module Traceparent = Otel.Trace_context.Traceparent in
    let headers =
      Header.add (Request.headers req) header_x_ocaml_otel_traceparent
        (Traceparent.to_value ~trace_id:(Otel.Span.trace_id span)
           ~parent_id:(Otel.Span.id span) ())
    in
    { req with headers }

  let get_trace_context ?(from = `Internal) req : Otel.Span.t option =
    let module Traceparent = Otel.Trace_context.Traceparent in
    let name =
      match from with
      | `Internal -> header_x_ocaml_otel_traceparent
      | `External -> Traceparent.name
    in
    match Header.get (Request.headers req) name with
    | None -> None
    | Some v ->
      (match Traceparent.of_value v with
      | Ok (trace_id, parent_id) ->
        (* TODO: we need a span_ctx here actually *)
        Some
          (Otel.Span.make ~trace_id ~id:parent_id ~start_time:0L ~end_time:0L "")
      | Error _ -> None)

  let remove_trace_context req =
    let headers =
      Header.remove (Request.headers req) header_x_ocaml_otel_traceparent
    in
    { req with headers }

  let trace ?(tracer = Otel.Tracer.dynamic_main) ?(attrs = []) callback conn req
      body =
    let parent = get_trace_context ~from:`External req in
    Otel_lwt.Tracer.with_ ~tracer "request" ~kind:Span_kind_server
      ?trace_id:(Option.map Otel.Span.trace_id parent)
      ?parent
      ~attrs:(attrs @ attrs_of_request req)
      (fun span ->
        let open Lwt.Syntax in
        let req = set_trace_context span req in
        let* res, body = callback conn req body in
        Otel.Span.add_attrs span (attrs_of_response res);
        Lwt.return (res, body))

  let with_ ?(tracer = Otel.Tracer.dynamic_main) ?trace_state ?attrs
      ?(kind = Otel.Span.Span_kind_internal) ?links name req
      (f : Request.t -> 'a Lwt.t) =
    let span = get_trace_context ~from:`Internal req in
    Otel_lwt.Tracer.with_ ~tracer ?trace_state ?attrs ~kind
      ?trace_id:(Option.map Otel.Span.trace_id span) ?parent:span ?links name
      (fun span ->
        let req = set_trace_context span req in
        f req)
end

let client ?(tracer = Otel.Tracer.dynamic_main) ?(span : Otel.Span.t option)
    (module C : Cohttp_lwt.S.Client) =
  let module Traced = struct
    open Lwt.Syntax

    (*   These types and values are not customized by our client, but are required to satisfy
         [Cohttp_lwt.S.Client]. *)
    include C

    let attrs_for ~uri ~meth () =
      [
        "http.method", `String (Code.string_of_method meth);
        "http.url", `String (Uri.to_string uri);
      ]

    let context_for ~uri ~meth =
      let parent =
        match span with
        | Some _ -> span
        | None -> Otel.Ambient_span.get ()
      in
      let trace_id = Option.map Otel.Span.trace_id parent in
      let attrs = attrs_for ~uri ~meth () in
      trace_id, parent, attrs

    let add_traceparent (span : Otel.Span.t) headers =
      let module Traceparent = Otel.Trace_context.Traceparent in
      let headers =
        match headers with
        | None -> Header.init ()
        | Some headers -> headers
      in
      Header.add headers Traceparent.name
        (Traceparent.to_value ~trace_id:(Otel.Span.trace_id span)
           ~parent_id:(Otel.Span.id span) ())

    let call ?ctx ?headers ?body ?chunked meth (uri : Uri.t) :
        (Response.t * Cohttp_lwt.Body.t) Lwt.t =
      let trace_id, parent, attrs = context_for ~uri ~meth in
      Otel_lwt.Tracer.with_ ~tracer "request" ~kind:Span_kind_client ?trace_id
        ?parent ~attrs (fun span ->
          let headers = add_traceparent span headers in
          let* res, body = C.call ?ctx ~headers ?body ?chunked meth uri in
          Otel.Span.add_attrs span (attrs_of_response res);
          Lwt.return (res, body))

    let head ?ctx ?headers uri =
      let open Lwt.Infix in
      call ?ctx ?headers `HEAD uri >|= fst

    let get ?ctx ?headers uri = call ?ctx ?headers `GET uri

    let delete ?ctx ?body ?chunked ?headers uri =
      call ?ctx ?headers ?body ?chunked `DELETE uri

    let post ?ctx ?body ?chunked ?headers uri =
      call ?ctx ?headers ?body ?chunked `POST uri

    let put ?ctx ?body ?chunked ?headers uri =
      call ?ctx ?headers ?body ?chunked `PUT uri

    let patch ?ctx ?body ?chunked ?headers uri =
      call ?ctx ?headers ?body ?chunked `PATCH uri

    let post_form ?ctx ?headers ~params uri =
      let trace_id, parent, attrs = context_for ~uri ~meth:`POST in
      Otel_lwt.Tracer.with_ ~tracer "request" ~kind:Span_kind_client ?trace_id
        ?parent ~attrs (fun span ->
          let headers = add_traceparent span headers in
          let* res, body = C.post_form ?ctx ~headers ~params uri in
          Otel.Span.add_attrs span (attrs_of_response res);
          Lwt.return (res, body))

    let callv = C.callv (* TODO *)
  end in
  (module Traced : Cohttp_lwt.S.Client)
