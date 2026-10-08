open Proto.Trace
open Opentelemetry_emitter

open struct
  let provider_ : Tracer.t Atomic.t = Atomic.make Tracer.dummy
end

(** Get current tracer. *)
let get () : Tracer.t = Atomic.get provider_

(** Set current tracer *)
let set (t : Tracer.t) : unit =
  Self_debug.log Info (fun () -> "otel: trace provider installed");
  Atomic.set provider_ t

(** Replace current tracer by the dummy one. All spans will be discarded from
    now on. *)
let clear () : unit =
  Self_debug.log Info (fun () -> "otel: trace provider removed");
  Atomic.set provider_ Tracer.dummy

(** Get a tracer pre-configured with a fixed set of attributes added to every
    span it emits, forwarding to the current global tracer. Intended to be
    called once at the top of a library module.

    @param name instrumentation scope name (recorded as [otel.scope.name])
    @param version
      instrumentation scope version (recorded as [otel.scope.version])
    @param __MODULE__
      the OCaml module name, typically the [__MODULE__] literal (recorded as
      [code.namespace])
    @param attrs additional fixed attributes *)
let get_tracer ?name ?version ?(attrs : (string * [< Value.t ]) list = [])
    ?__MODULE__ () : Tracer.t =
  let extra =
    Scope_attributes.make_attrs ?name ?version ~attrs ?__MODULE__ ()
  in
  {
    Tracer.emit =
      Emitter.make ~signal_name:"spans"
        ~enabled:(fun () -> Emitter.enabled (Atomic.get provider_).emit)
        ~emit:(fun spans ->
          (match extra with
          | [] -> ()
          | _ -> List.iter (fun span -> Span.add_attrs span extra) spans);
          Emitter.emit (Atomic.get provider_).emit spans)
        ();
    clock = { Clock.now = (fun () -> Clock.now (Clock.Main.get ())) };
  }

(** A Tracer.t that lazily reads the global at emit time *)
let default_tracer : Tracer.t = get_tracer ()

(** Emit a span directly via the current global tracer *)
let[@inline] emit (span : Span.t) : unit = Emitter.emit (get ()).emit [ span ]

(** Helper to implement {!with_} and similar functions *)
let with_thunk_and_finally (self : Tracer.t) ?(force_new_trace_id = false)
    ?trace_state ?(attrs : (string * [< Value.t ]) list = []) ?kind ?trace_id
    ?parent ?parent_ctx ?links name cb =
  let parent =
    match parent, parent_ctx with
    | Some _, _ | None, Some _ -> parent
    | None, None -> Ambient_span.get ()
  in
  let parent_ctx =
    match parent with
    | Some _ -> None
    | None -> parent_ctx
  in
  let trace_id =
    match trace_id, parent, parent_ctx with
    | _ when force_new_trace_id -> Trace_id.create ()
    | Some trace_id, _, _ -> trace_id
    | None, Some p, _ -> Span.trace_id p
    | None, None, Some c -> Span_ctx.trace_id c
    | None, None, None -> Trace_id.create ()
  in
  let start_time = Clock.now self.clock in
  let span_id = Span_id.create () in

  let parent_id =
    match parent, parent_ctx with
    | Some p, _ -> Some (Span.id p)
    | None, Some c -> Some (Span_ctx.parent_id c)
    | None, None -> None
  in

  let sampled, trace_state =
    let[@inline] of_bool b : Trace_sampler.parent =
      if b then
        Parent_sampled
      else
        Parent_not_sampled
    in
    let parent, parent_ts =
      match parent, parent_ctx with
      | Some p, _ -> of_bool (Span.sampled p), p.trace_state
      | None, Some c -> of_bool (Span_ctx.sampled c), Span_ctx.trace_state c
      | None, None -> No_parent, ""
    in
    let trace_state = Option.value trace_state ~default:parent_ts in
    Trace_sampler.decide_current ~parent ~trace_state trace_id
  in
  let trace_state =
    match trace_state with
    | "" -> None
    | ts -> Some ts
  in

  let span : Span.t =
    Span.make ~sampled ?trace_state ?kind ?parent:parent_id ~trace_id
      ~id:span_id
      ~attrs:
        (if sampled then
           attrs
         else
           [])
      ?links ~start_time ~end_time:start_time name
  in
  let () =
    if sampled then (
      match Dynamic_enricher.collect () with
      | [] -> ()
      | dyn_attrs -> Span.add_attrs span dyn_attrs
    )
  in
  (* called once we're done, to emit a span *)
  let finally res =
    let end_time = Clock.now self.clock in
    span_set_end_time_unix_nano span end_time;

    (match Span.status span with
    | Some _ -> ()
    | None ->
      (match res with
      | Ok () -> ()
      | Error (e, bt) -> Span.record_exception span e bt));

    if sampled then Emitter.emit self.emit [ span ]
  in
  let thunk () = Ambient_span.with_ambient span (fun () -> cb span) in
  thunk, finally

(** Sync span guard.

    Notably, this includes {e implicit} scope-tracking: if called without a
    [~scope] argument (or [~parent]/[~trace_id]), it will check in the
    {!Ambient_context} for a surrounding environment, and use that as the scope.
    Similarly, it uses {!Scope.with_ambient_scope} to {e set} a new scope in the
    ambient context, so that any logically-nested calls to {!with_} will use
    this span as their parent.

    {b NOTE} be careful not to call this inside a Gc alarm, as it can cause
    deadlocks.

    @param tracer the tracer to use (default [default_tracer])
    @param force_new_trace_id
      if true (default false), the span will not use a ambient scope, the
      [~scope] argument, nor [~trace_id], but will instead always create fresh
      identifiers for this span
    @param parent_ctx
      parent span context, e.g. from an incoming [traceparent]. [~parent] takes
      precedence; both take precedence over the ambient span. Since NEXT_RELEASE
*)
let with_ ?(tracer = default_tracer) ?force_new_trace_id ?trace_state ?attrs
    ?kind ?trace_id ?parent ?parent_ctx ?links name (cb : Span.t -> 'a) : 'a =
  let thunk, finally =
    with_thunk_and_finally tracer ?force_new_trace_id ?trace_state ?attrs ?kind
      ?trace_id ?parent ?parent_ctx ?links name cb
  in
  try
    let rv = thunk () in
    finally (Ok ());
    rv
  with e ->
    let bt = Printexc.get_raw_backtrace () in
    finally (Error (e, bt));
    raise e
