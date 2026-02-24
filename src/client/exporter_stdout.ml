(** A simple exporter that prints on stdout. *)

open Common_

open struct
  let pp_span out (sp : OTEL.Span.t) =
    let open OTEL in
    Format.fprintf out
      "@[<2>SPAN {@ trace_id: %a@ span_id: %a@ name: %S@ start: %a@ end: %a@ \
       dur: %.6fs@]}"
      Trace_id.pp
      (Trace_id.of_bytes sp.trace_id)
      Span_id.pp
      (Span_id.of_bytes sp.span_id)
      sp.name Timestamp_ns.pp_debug sp.start_time_unix_nano
      Timestamp_ns.pp_debug sp.end_time_unix_nano
      ((Int64.to_float sp.end_time_unix_nano
       -. Int64.to_float sp.start_time_unix_nano)
      /. 1e9)

  let pp_log out l =
    Format.fprintf out "@[<2>LOG %a@]" Proto.Logs.pp_log_record l

  let pp_metric out m =
    Format.fprintf out "@[<2>METRICS %a@]" Proto.Metrics.pp_metric m

  let pp_vlist mutex pp out l =
    if l != [] then (
      let@ () = Util_mutex.protect mutex in
      Format.fprintf out "@[<v>";
      List.iteri
        (fun i x ->
          if i > 0 then Format.fprintf out "@,";
          pp out x)
        l;
      Format.fprintf out "@]@."
    )
end

let stdout ?(clock = OTEL.Clock.ptime_clock) () : OTEL.Exporter.t =
  let open Opentelemetry_util in
  ignore clock;
  let out = Format.std_formatter in
  let mutex = Mutex.create () in

  let export (sig_ : OTEL.Any_signal_l.t) =
    match sig_ with
    | OTEL.Any_signal_l.Spans sp -> pp_vlist mutex pp_span out sp
    | OTEL.Any_signal_l.Logs logs -> pp_vlist mutex pp_log out logs
    | OTEL.Any_signal_l.Metrics ms -> pp_vlist mutex pp_metric out ms
  in

  let shutdown () =
    let@ () = Util_mutex.protect mutex in
    Format.pp_print_flush out ()
  in

  {
    OTEL.Exporter.export;
    active = (fun () -> Aswitch.dummy);
    shutdown;
    self_metrics = (fun () -> []);
  }
