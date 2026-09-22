open Opentelemetry_emitter

open struct
  let provider_ : Meter.t Atomic.t = Atomic.make Meter.dummy
end

let get () : Meter.t = Atomic.get provider_

let set (t : Meter.t) : unit =
  Self_debug.log Info (fun () -> "otel: meter provider installed");
  Atomic.set provider_ t

let clear () : unit =
  Self_debug.log Info (fun () -> "otel: meter provider removed");
  Atomic.set provider_ Meter.dummy

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

(** Emit with current meter *)
let[@inline] emit (m : Metrics.t) : unit = Emitter.emit (get ()).emit [ m ]

(** Emit a list of metrics with current meter *)
let[@inline] emit_l (ms : Metrics.t list) : unit = Emitter.emit (get ()).emit ms

(** A Meter.t that lazily reads the global at emit time *)
let default_meter : Meter.t = get_meter ()

open struct
  let minimum_min_interval_ = Mtime.Span.(100 * ms)

  let default_min_interval_ = Mtime.Span.(30 * s)

  let global_min_interval : Mtime.span Atomic.t =
    Atomic.make default_min_interval_

  let clamp_interval_ interval =
    if Mtime.Span.compare interval minimum_min_interval_ < 0 then
      minimum_min_interval_
    else
      interval
end

(** Set the global minimum interval between two periodic collections (default
    30s), clamped to at least 100ms. Affects the global meter provider and every
    {!add_periodic_collection} that didn't pass its own [min_interval]. *)
let set_min_interval (i : Mtime.span) : unit =
  Atomic.set global_min_interval (clamp_interval_ i)

(** Collect all instruments and callbacks, and emit the result into [m]. Does
    nothing if [m] is disabled. *)
let collect_and_emit (m : Meter.t) : unit =
  if Meter.enabled m then (
    let metrics = Meter.collect m in
    if metrics <> [] then Emitter.emit m.emit metrics
  )

(** [add_periodic_collection meter] registers a tick callback that periodically
    collects all instruments (see {!Meter.collect}) and emits them into the
    current value of [meter], if it is enabled.

    The global meter provider is already registered this way, so this is only
    needed to export metrics to an additional destination.

    @param min_interval
      minimum interval between collections, read at each tick. Defaults to the
      global interval, so later calls to {!set_min_interval} apply. A custom
      atomic is not clamped.

    @since NEXT_RELEASE *)
let add_periodic_collection ?(min_interval = global_min_interval)
    (meter : Meter.t Atomic.t) : unit =
  let limiter = Interval_limiter.create_atomic ~min_interval () in
  Globals.add_on_tick_callback (fun () ->
      let m = Atomic.get meter in
      (* check [enabled] first so that we don't consume the interval
         while disabled *)
      if Meter.enabled m && Interval_limiter.make_attempt limiter then
        collect_and_emit m)

(* the global provider is always collected periodically *)
let () = add_periodic_collection ~min_interval:global_min_interval provider_
