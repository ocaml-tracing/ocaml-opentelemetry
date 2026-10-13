open Opentelemetry

(** Check that Span.dummy is never modified by mutation functions *)

let check_pristine () =
  let d = Span.dummy in
  assert (Span.attrs d = []);
  assert (Span.events d = []);
  assert (Span.links d = []);
  assert (Span.status d = None);
  assert (Span.kind d = None);
  assert (not ((Span.is_not_dummy [@alert "-expert"]) d))

let check name f =
  f ();
  check_pristine ();
  Printf.printf "ok: %s\n" name

let trace_id = Trace_id.create ()

let span_id = Span_id.create ()

let () =
  check_pristine ();
  check "add_attrs" (fun () -> Span.add_attrs Span.dummy [ "k", `String "v" ]);
  check "add_attrs'" (fun () ->
      Span.add_attrs' Span.dummy (fun () -> [ "k", `Int 42 ]));
  check "add_event" (fun () -> Span.add_event Span.dummy (Event.make "ev"));
  check "add_event'" (fun () ->
      Span.add_event' Span.dummy (fun () -> Event.make "ev"));
  check "add_links" (fun () ->
      Span.add_links Span.dummy [ Span_link.make ~trace_id ~span_id () ]);
  check "add_links'" (fun () ->
      Span.add_links' Span.dummy (fun () ->
          [ Span_link.make ~trace_id ~span_id () ]));
  check "set_status" (fun () ->
      Span.set_status Span.dummy
        (Span_status.make ~message:"err" ~code:Span_status.Status_code_error));
  check "set_kind" (fun () -> Span.set_kind Span.dummy Span_kind_server);
  check "record_exception" (fun () ->
      try raise Exit
      with exn ->
        let bt = Printexc.get_raw_backtrace () in
        Span.record_exception Span.dummy exn bt);
  Format.printf "span dummy at the end: %a@." Opentelemetry_proto.Trace.pp_span
    Span.dummy;
  print_endline "all ok"
