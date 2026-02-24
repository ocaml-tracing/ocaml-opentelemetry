open Opentelemetry_emitter

open struct
  let provider_ : Meter.t Atomic.t = Atomic.make Meter.dummy
end

let get () : Meter.t = Atomic.get provider_

let set (t : Meter.t) : unit = Atomic.set provider_ t

let clear () : unit = Atomic.set provider_ Meter.dummy

(** Get a meter pre-configured with a fixed set of attributes added to every
    metric it emits, forwarding to the current global meter. Intended to be
    called once at the top of a library module.

    @param name instrumentation scope name (recorded as [otel.scope.name])
    @param version
      instrumentation scope version (recorded as [otel.scope.version])
    @param __MODULE__
      the OCaml module name, typically the [__MODULE__] literal (recorded as
      [code.namespace])
    @param attrs additional fixed attributes *)
let get_meter ?name ?version ?(attrs : (string * [< Value.t ]) list = [])
    ?__MODULE__ () : Meter.t =
  let extra =
    Scope_attributes.make_attrs ?name ?version ~attrs ?__MODULE__ ()
  in
  {
    Meter.emit =
      Emitter.make ~signal_name:"metrics"
        ~enabled:(fun () -> Emitter.enabled (Atomic.get provider_).emit)
        ~emit:(fun metrics ->
          (match extra with
          | [] -> ()
          | _ -> List.iter (fun m -> Metrics.add_attrs m extra) metrics);
          Emitter.emit (Atomic.get provider_).emit metrics)
        ();
    clock = { Clock.now = (fun () -> Clock.now (Clock.Main.get ())) };
  }

(** A Meter.t that lazily reads the global at emit time *)
let default_meter : Meter.t = get_meter ()

let minimum_min_interval_ = Mtime.Span.(100 * ms)

let default_min_interval_ = Mtime.Span.(4 * s)

let clamp_interval_ interval =
  if Mtime.Span.is_shorter interval ~than:minimum_min_interval_ then
    minimum_min_interval_
  else
    interval

let add_to_exporter ?(min_interval = default_min_interval_) (_exp : Exporter.t)
    (self : Meter.t) : unit =
  let limiter =
    Interval_limiter.create ~min_interval:(clamp_interval_ min_interval) ()
  in
  Globals.add_on_tick_callback (fun () ->
      if Interval_limiter.make_attempt limiter then (
        let metrics = Meter.collect self in
        if metrics <> [] then Emitter.emit self.emit metrics
      ))

let add_to_main_exporter ?(min_interval = default_min_interval_)
    (self : Meter.t) : unit =
  let limiter =
    Interval_limiter.create ~min_interval:(clamp_interval_ min_interval) ()
  in
  Globals.add_on_tick_callback (fun () ->
      if Interval_limiter.make_attempt limiter then (
        let metrics = Meter.collect self in
        if metrics <> [] then Emitter.emit self.emit metrics
      ))
