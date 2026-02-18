(** A simple exporter that prints on stdout. *)

open Common_
open Opentelemetry_emitter

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
  let out = Format.std_formatter in
  let mutex = Mutex.create () in
  let ticker = Cb_set.create () in

  let active, trigger = Aswitch.create () in
  let tick () = Cb_set.trigger ticker in

  let mk_emitter ~signal_name pp_signal =
    let emit l =
      if Aswitch.is_off active then raise Emitter.Closed;
      pp_vlist mutex pp_signal out l
    in
    let enabled () = Aswitch.is_on active in
    let self_metrics ~now:_ () = [] in
    let tick ~mtime:_ = () in
    let flush_and_close () =
      if Aswitch.is_on active then
        let@ () = Util_mutex.protect mutex in
        Format.pp_print_flush out ()
    in
    let closed () = Aswitch.is_off active in
    {
      Emitter.emit;
      signal_name;
      self_metrics;
      closed;
      enabled;
      tick;
      flush_and_close;
    }
  in

  let emit_spans = mk_emitter ~signal_name:"spans" pp_span in
  let emit_logs = mk_emitter ~signal_name:"logs" pp_log in
  let emit_metrics = mk_emitter ~signal_name:"metrics" pp_metric in

  let self_metrics () = [] in
  let shutdown () =
    Emitter.flush_and_close emit_spans;
    Emitter.flush_and_close emit_logs;
    Emitter.flush_and_close emit_metrics;
    Aswitch.turn_off trigger
  in

  {
    active = (fun () -> active);
    clock;
    emit_spans;
    emit_logs;
    emit_metrics;
    on_tick = Cb_set.register ticker;
    self_metrics;
    tick;
    shutdown;
  }
