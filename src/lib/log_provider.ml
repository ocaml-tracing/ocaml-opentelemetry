open Opentelemetry_emitter

open struct
  let provider_ : Logger.t Atomic.t = Atomic.make Logger.dummy
end

let get () : Logger.t = Atomic.get provider_

let set (t : Logger.t) : unit = Atomic.set provider_ t

let clear () : unit = Atomic.set provider_ Logger.dummy

(** Get a logger pre-configured with a fixed set of attributes added to every
    log record it emits, forwarding to the current global logger. Intended to be
    called once at the top of a library module.

    @param name instrumentation scope name (recorded as [otel.scope.name])
    @param version
      instrumentation scope version (recorded as [otel.scope.version])
    @param __MODULE__
      the OCaml module name, typically the [__MODULE__] literal (recorded as
      [code.namespace])
    @param attrs additional fixed attributes *)
let get_logger ?name ?version ?(attrs : (string * [< Value.t ]) list = [])
    ?__MODULE__ () : Logger.t =
  let extra =
    Scope_attributes.make_attrs ?name ?version ~attrs ?__MODULE__ ()
  in
  {
    Logger.emit =
      Emitter.make ~signal_name:"logs"
        ~enabled:(fun () -> Emitter.enabled (Atomic.get provider_).emit)
        ~emit:(fun logs ->
          (match extra with
          | [] -> ()
          | _ -> List.iter (fun log -> Log_record.add_attrs log extra) logs);
          Emitter.emit (Atomic.get provider_).emit logs)
        ();
    clock = { Clock.now = (fun () -> Clock.now (Clock.Main.get ())) };
  }

(** A Logger.t that lazily reads the global at emit time *)
let default_logger : Logger.t = get_logger ()

open Log_record

(** Create log record and emit it on [logger] *)
let log ?(logger = default_logger) ?attrs ?trace_id ?span_id
    ?(severity : severity option) (msg : string) : unit =
  if Logger.enabled logger then (
    let now = Clock.now logger.clock in
    let dyn_attrs = Dynamic_enricher.collect () in
    let attrs =
      match dyn_attrs with
      | [] -> attrs
      | _ ->
        let base = Option.value ~default:[] attrs in
        Some (List.rev_append dyn_attrs base)
    in
    let logrec =
      Log_record.make_str ?attrs ?trace_id ?span_id ?severity
        ~observed_time_unix_nano:now msg
    in
    Logger.emit1 logger logrec
  )

(** Helper to create a log record, with a suspension, like in [Logs].

    Example usage:
    [logf ~severity:Severity_number_warn (fun k->k"oh no!! %s it's bad: %b"
     "help" true)] *)
let logf ?(logger = default_logger) ?attrs ?trace_id ?span_id ?severity msgf :
    unit =
  if Logger.enabled logger then
    msgf (fun fmt ->
        Format.kasprintf (log ~logger ?attrs ?trace_id ?span_id ?severity) fmt)
