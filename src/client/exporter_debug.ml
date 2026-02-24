(** Basic debug exporter, prints signals on stdout/stderr/...

    As the name says, it's not intended for production but as a quick way to
    export signals and eyeball them. *)

open Common_

(** [debug ?out ()] is an exporter that pretty-prints signals on [out].
    @param out the formatter into which to print, default [stderr]. *)
let debug ?(clock = OTEL.Clock.ptime_clock) ?(out = Format.err_formatter) () :
    OTEL.Exporter.t =
  ignore clock;
  let open Proto in
  {
    OTEL.Exporter.export =
      (fun sig_ ->
        match sig_ with
        | OTEL.Any_signal_l.Spans sp ->
          List.iter (Format.fprintf out "SPAN: %a@." Trace.pp_span) sp
        | OTEL.Any_signal_l.Metrics ms ->
          List.iter (Format.fprintf out "METRIC: %a@." Metrics.pp_metric) ms
        | OTEL.Any_signal_l.Logs logs ->
          List.iter
            (Format.fprintf out "LOG: %a@." Proto.Logs.pp_log_record)
            logs);
    active = (fun () -> Aswitch.dummy);
    shutdown =
      (fun () ->
        Format.fprintf out "CLEANUP@.";
        ());
    self_metrics = (fun () -> []);
  }
