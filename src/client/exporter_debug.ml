(** Basic debug exporter, prints signals on stdout/stderr/...

    As the name says, it's not intended for production but as a quick way to
    export signals and eyeball them. *)

open Common_
open Opentelemetry_emitter

(** [debug ?out ()] is an exporter that pretty-prints signals on [out].
    @param out the formatter into which to print, default [stderr]. *)
let debug ?(clock = OTEL.Clock.ptime_clock) ?(out = Format.err_formatter) () :
    OTEL.Exporter.t =
  let open Proto in
  let active, trigger = Aswitch.create () in
  let ticker = Cb_set.create () in
  {
    active = (fun () -> active);
    clock;
    emit_spans =
      Emitter.make ~signal_name:"spans" () ~emit:(fun sp ->
          List.iter (Format.fprintf out "SPAN: %a@." Trace.pp_span) sp);
    emit_logs =
      Emitter.make ~signal_name:"logs" () ~emit:(fun log ->
          List.iter
            (Format.fprintf out "LOG: %a@." Proto.Logs.pp_log_record)
            log);
    emit_metrics =
      Emitter.make ~signal_name:"metrics" () ~emit:(fun m ->
          List.iter (Format.fprintf out "METRIC: %a@." Metrics.pp_metric) m);
    on_tick = Cb_set.register ticker;
    tick = (fun () -> Cb_set.trigger ticker);
    self_metrics = (fun () -> []);
    shutdown =
      (fun () ->
        Format.fprintf out "CLEANUP@.";
        Aswitch.turn_off trigger);
  }
