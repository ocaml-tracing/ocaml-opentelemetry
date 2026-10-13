open Opentelemetry

let sent = ref None

module Client = struct
  include Cohttp_lwt_unix.Client

  let call ?ctx:_ ?headers ?body:_ ?chunked:_ _ _ =
    sent := headers;
    Lwt.return (Cohttp.Response.make (), Cohttp_lwt.Body.empty)
end

let span =
  Span.make
    ~trace_id:(Trace_id.of_hex "4bf92f3577b34da6a3ce929d0e0e4736")
    ~id:(Span_id.of_hex "00f067aa0ba902b7")
    ~trace_state:"ot=th:8" ~start_time:0L ~end_time:0L "test"

let test ~span ~expected_state () =
  let headers =
    Cohttp.Header.of_list
      [
        "traceparent", "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00";
        "tracestate", "old=1";
        "x-custom", "keep";
      ]
  in
  let (module C : Cohttp_lwt.S.Client) =
    Opentelemetry_cohttp_lwt.client ~span (module Client)
  in
  ignore (Lwt_main.run (C.get ~headers (Uri.of_string "http://localhost/")));
  let headers = Option.get !sent in
  let traceparent = Cohttp.Header.get_multi headers "traceparent" in
  assert (List.length traceparent = 1);
  let ctx =
    Result.get_ok (Trace_context.Traceparent.of_value (List.hd traceparent))
  in
  assert (
    Trace_id.to_hex (Span_ctx.trace_id ctx)
    = Trace_id.to_hex (Span.trace_id span));
  assert (Span_ctx.sampled ctx);
  assert (Cohttp.Header.get_multi headers "tracestate" = expected_state);
  assert (Cohttp.Header.get headers "x-custom" = Some "keep")

let () = test ~span ~expected_state:[ "ot=th:8" ] ()

let () =
  let span =
    Span.make ~trace_id:(Span.trace_id span) ~id:(Span_id.create ())
      ~start_time:0L ~end_time:0L "test"
  in
  test ~span ~expected_state:[] ()
