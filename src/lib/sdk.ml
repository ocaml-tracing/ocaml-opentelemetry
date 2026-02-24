(** SDK setup.

    Convenience module for installing a single {!Exporter.t} as the global
    backend, wiring it into {!Trace_provider}, {!Meter_provider}, and
    {!Log_provider} at once. Optionally applies per-signal batching. *)

open Opentelemetry_emitter

open struct
  let exporter : Exporter.t option Atomic.t = Atomic.make None
end

(** Remove current exporter, if any.
    @param on_done called once the exporter has fully shut down (queue drained).
*)
let remove ~on_done () : unit =
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

let add_on_tick_callback (f : unit -> unit) : unit =
  Globals.add_on_tick_callback f

let run_tick_callbacks () : unit = Globals.run_tick_callbacks ()

(** Tick all providers and run all registered callbacks. Call this periodically
    (e.g. every 500ms) to drive metrics collection, GC metrics, and batch
    timeout flushing. This is the single function client libraries should call
    from their ticker. *)
let tick () : unit = Globals.run_tick_callbacks ()

let set ?batch_traces ?batch_metrics ?batch_logs
    ?(batch_timeout = Mtime.Span.(2_000 * ms)) (exp : Exporter.t) : unit =
  Atomic.set exporter (Some exp);
  let tracer : Tracer.t =
    let t = Tracer.of_exporter exp in
    {
      t with
      emit =
        Emitter_batch.add_batching_opt ~timeout:batch_timeout
          ~batch_size:batch_traces t.emit;
    }
  in
  let meter : Meter.t =
    let m = Meter.of_exporter exp in
    {
      m with
      emit =
        Emitter_batch.add_batching_opt ~timeout:batch_timeout
          ~batch_size:batch_metrics m.emit;
    }
  in
  let logger : Logger.t =
    let l = Logger.of_exporter exp in
    {
      l with
      emit =
        Emitter_batch.add_batching_opt ~timeout:batch_timeout
          ~batch_size:batch_logs l.emit;
    }
  in
  Trace_provider.set tracer;
  Meter_provider.set meter;
  Log_provider.set logger

let self_metrics () : Metrics.t list =
  match get () with
  | None -> []
  | Some exp -> exp.Exporter.self_metrics ()

(* Permanent tick callback to drive batch timeouts on provider emitters *)
let () =
  Globals.add_on_tick_callback (fun () ->
      let mtime = Mtime_clock.now () in
      Emitter.tick (Trace_provider.get ()).emit ~mtime;
      Emitter.tick (Meter_provider.get ()).emit ~mtime;
      Emitter.tick (Log_provider.get ()).emit ~mtime)
