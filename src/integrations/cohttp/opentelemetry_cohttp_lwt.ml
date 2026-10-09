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
  [@@deprecated "use Opentelemetry_lwt.Tracer.with_"]
  (** Trace a new internal span, parented to the ambient span. [req] is passed
      through unchanged. *)

  val get_trace_context : Request.t -> Otel.Span_ctx.t option
  (** Remote span context from the W3C [traceparent] and [tracestate] headers.
      @since NEXT_RELEASE returns a {!Otel.Span_ctx.t}, no [?from] *)
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

  let get_trace_context req : Otel.Span_ctx.t option =
    let open Otel.Trace_context in
    let headers = Request.headers req in
    match Header.get headers Traceparent.name with
    | None -> None
    | Some v ->
      let trace_state = Header.get headers Tracestate.name in
      Result.to_option (Traceparent.of_value ?trace_state v)

  let trace ?(tracer = Otel.Tracer.default) ?(attrs = []) callback conn req body
      =
    let parent_ctx = get_trace_context req in
    Otel_lwt.Tracer.with_ ~tracer "request" ~kind:Span_kind_server ?parent_ctx
      ~attrs:(attrs @ attrs_of_request req)
      (fun span ->
        let open Lwt.Syntax in
        let* res, body = callback conn req body in
        Otel.Span.add_attrs span (attrs_of_response res);
        Lwt.return (res, body))

  let with_ ?(tracer = Otel.Tracer.default) ?trace_state ?attrs
      ?(kind = Otel.Span.Span_kind_internal) ?links name req
      (f : Request.t -> 'a Lwt.t) =
    Otel_lwt.Tracer.with_ ~tracer ?trace_state ?attrs ~kind ?links name
      (fun _ -> f req)
end

let client ?(tracer = Otel.Tracer.default) ?(span : Otel.Span.t option)
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
      let headers =
        match headers with
        | None -> Header.init ()
        | Some headers -> headers
      in
      let headers =
        Header.remove (Header.remove headers "traceparent") "tracestate"
      in
      Header.add_list headers
        (Otel.Trace_context.headers_of_span_ctx (Otel.Span.to_span_ctx span))

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
