(** SDK setup.

    Convenience module for installing a single {!Exporter.t} as the global
    backend, wiring it into {!Trace_provider}, {!Meter_provider}, and
    {!Log_provider} at once. Optionally applies per-signal batching. *)

open Opentelemetry_emitter

open struct
  let exporter : Exporter.t option Atomic.t = Atomic.make None
end

let self_debug_to_stderr = Self_debug.to_stderr

(** Remove current exporter, if any.
    @param on_done called once the exporter has fully shut down (queue drained).
*)
let remove ~on_done () : unit =
  Self_debug.log Info (fun () -> "opentelemetry: SDK removed");
  (* flush+close provider emitters so buffered signals reach the queue *)
  Emitter.flush_and_close (Trace_provider.get ()).emit;
  Emitter.flush_and_close (Meter_provider.get ()).emit;
  Emitter.flush_and_close (Log_provider.get ()).emit;

  (* clear providers — no new signals accepted *)
  Trace_provider.clear ();
  Meter_provider.clear ();
  Log_provider.clear ();
  match Atomic.exchange exporter None with
  | None -> on_done ()
  | Some exp ->
    (* wait for exporter to fully drain, then call on_done *)
    Aswitch.on_turn_off (Exporter.active exp) on_done;
    (* initiate shutdown (closes queue, starts consumer drain) *)
    Exporter.shutdown exp

let[@inline] present () : bool = Option.is_some (Atomic.get exporter)

let[@inline] get () : Exporter.t option = Atomic.get exporter

(** Aswitch of the installed exporter, or {!Aswitch.dummy} if none. *)
let[@inline] active () : Aswitch.t =
  match Atomic.get exporter with
  | None -> Aswitch.dummy
  | Some exp -> Exporter.active exp

let add_on_tick_callback : (unit -> unit) -> unit = Globals.add_on_tick_callback

let run_tick_callbacks : unit -> unit = Globals.run_tick_callbacks

(** Tick all providers and run all registered callbacks. Call this periodically
    (e.g. every 500ms) to drive metrics collection, GC metrics, and batch
    timeout flushing. This is the single function client libraries should call
    from their ticker. *)
let tick : unit -> unit = Globals.run_tick_callbacks

let set ?(traces = Provider_config.make ~batch:400 ())
    ?(metrics = Provider_config.make ~batch:200 ())
    ?(logs = Provider_config.make ~batch:400 ()) (exp : Exporter.t) : unit =
  Self_debug.log Info (fun () -> "opentelemetry: SDK set up");
  Atomic.set exporter (Some exp);
  let tracer : Tracer.t =
    let t = Tracer.of_exporter exp in
    {
      t with
      emit =
        Emitter_batch.add_batching_opt ~timeout:traces.Provider_config.timeout
          ~batch_size:traces.Provider_config.batch t.emit;
    }
  in
  let meter : Meter.t =
    let m = Meter.of_exporter exp in
    {
      m with
      emit =
        Emitter_batch.add_batching_opt ~timeout:metrics.Provider_config.timeout
          ~batch_size:metrics.Provider_config.batch m.emit;
    }
  in
  let logger : Logger.t =
    let l = Logger.of_exporter exp in
    {
      l with
      emit =
        Emitter_batch.add_batching_opt ~timeout:logs.Provider_config.timeout
          ~batch_size:logs.Provider_config.batch l.emit;
    }
  in
  Trace_provider.set tracer;
  Meter_provider.set meter;
  Log_provider.set logger

let self_metrics () : Metrics.t list =
  let now = Clock.now_main () in
  let emitter_metrics =
    Emitter.self_metrics (Trace_provider.get ()).emit ~now
    @ Emitter.self_metrics (Meter_provider.get ()).emit ~now
    @ Emitter.self_metrics (Log_provider.get ()).emit ~now
  in
  match get () with
  | None -> emitter_metrics
  | Some exp -> exp.Exporter.self_metrics () @ emitter_metrics

open struct
  let self_metrics_enabled = Atomic.make false
end

(** Regularly emit metrics about the OTEL SDK. Idempotent. *)
let setup_self_metrics () =
  if not (Atomic.exchange self_metrics_enabled true) then (
    Self_debug.log Info (fun () -> "enabling self metrics");
    let interval_limiter =
      Interval_limiter.create ~min_interval:Mtime.Span.(10 * s) ()
    in
    let on_tick () =
      if Interval_limiter.make_attempt interval_limiter then (
        let ms = self_metrics () in
        Meter_provider.emit_l ms
      )
    in
    Globals.add_on_tick_callback on_tick
  )

(* Permanent tick callback to drive batch timeouts on provider emitters *)
let () =
  Globals.add_on_tick_callback (fun () ->
      let mtime = Mtime_clock.now () in
      Emitter.tick (Trace_provider.get ()).emit ~mtime;
      Emitter.tick (Meter_provider.get ()).emit ~mtime;
      Emitter.tick (Log_provider.get ()).emit ~mtime)
