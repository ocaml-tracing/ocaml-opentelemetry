open Common_

module Extensions = struct
  (* extend [Trace]'s types with OTEL specific variants, eg to have a
     [Trace.span] be a wrapper around [OTEL.Span.t], or to declare custom actions
     to link spans together, or to be able to use [OTEL]-specific metrics types *)
  type Trace.span += Span_otel of OTEL.Span.t

  type Trace.extension_event +=
    | Ev_link_span of Trace.span * OTEL.Span_ctx.t
    | Ev_record_exn of {
        sp: Trace.span;
        exn: exn;
        bt: Printexc.raw_backtrace;
      }
    | Ev_set_span_kind of Trace.span * OTEL.Span_kind.t
    | Ev_set_span_status of Trace.span * OTEL.Span_status.t

  type Trace.metric +=
    | Metric_hist of OTEL.Metrics.histogram_data_point
    | Metric_sum_int of int
    | Metric_sum_float of float
end

open Extensions

(* Inject ambient span into [Trace], relying on the [Ambient_context]
   library. We use the generic ambient context to carry a [Hmap.t] around with
   possible the current [Trace.span], and it is also used by [OTEL] itself
   (ambient [OTEL.Span_ctx.t]).

   This mechanism is used by [Trace] so that nested [Trace.with_span] can infer
   the correct parent-child relation from implicit context, and produce OTEL
   spans accordingly; without it every span would be parentless. *)
module Ambient_span_provider_ = struct
  let get_current_span () =
    match OTEL.Ambient_span.get () with
    | None -> None
    | Some sp -> Some (Span_otel sp)

  let with_current_span_set_to () span f =
    match span with
    | Span_otel sp -> OTEL.Ambient_span.with_ambient sp (fun () -> f span)
    | _ -> f span

  let callbacks : unit Trace.Ambient_span_provider.Callbacks.t =
    { get_current_span; with_current_span_set_to }

  let provider = Trace.Ambient_span_provider.ASP_some ((), callbacks)
end

let ambient_span_provider = Ambient_span_provider_.provider

open struct
  type state = unit

  (* sanity check: otrace meta-map must be the same as hmap *)
  let () = ignore (fun (k : _ Hmap.key) : _ Ambient_context.Context.key -> k)

  (** Key to access the current span context. Uses the shared key from core. *)
  let k_span_ctx : OTEL.Span_ctx.t Ambient_context.Context.key =
    OTEL.Span_ctx.k_ambient

  let enter_span () ~__FUNCTION__ ~__FILE__ ~__LINE__ ~level:_ ~params:_
      ~(data : (_ * Trace.user_data) list) ~parent name : Trace.span =
    let start_time = OTEL.Clock.now_main () in
    let trace_id, parent_id =
      match parent with
      | Trace.P_none -> OTEL.Trace_id.create (), None
      | Trace.P_some (Span_otel sp) ->
        OTEL.Span.trace_id sp, Some (OTEL.Span.id sp)
      | _ ->
        (match Ambient_context.get k_span_ctx with
        | Some sp_ctx ->
          OTEL.Span_ctx.trace_id sp_ctx, Some (OTEL.Span_ctx.parent_id sp_ctx)
        | None -> OTEL.Trace_id.create (), None)
    in

    let span_id = OTEL.Span_id.create () in

    let attrs =
      ("code.filepath", `String __FILE__)
      :: ("code.lineno", `Int __LINE__)
      :: data
    in

    let otel_sp : OTEL.Span.t =
      OTEL.Span.make ~start_time ~id:span_id ~trace_id ~attrs ?parent:parent_id
        ~end_time:0L name
    in

    (* add more data if [__FUNCTION__] is present *)
    (match __FUNCTION__ with
    | Some __FUNCTION__ when OTEL.Span.is_not_dummy otel_sp ->
      let function_name, module_path =
        try
          let last_dot = String.rindex __FUNCTION__ '.' in
          let module_path = String.sub __FUNCTION__ 0 last_dot in
          let function_name =
            String.sub __FUNCTION__ (last_dot + 1)
              (String.length __FUNCTION__ - last_dot - 1)
          in
          function_name, Some module_path
        with Not_found ->
          (* __FUNCTION__ has no dot, use it as-is *)
          __FUNCTION__, None
      in
      let attrs =
        ("code.function", `String function_name)
        ::
        (match module_path with
        | Some module_path -> [ "code.namespace", `String module_path ]
        | None -> [])
      in
      OTEL.Span.add_attrs otel_sp attrs
    | _ -> ());

    Span_otel otel_sp

  let exit_span () sp =
    match sp with
    | Span_otel span when OTEL.Span.is_not_dummy span ->
      (* emit the span after setting the end timestamp *)
      let end_time = OTEL.Clock.now_main () in
      OTEL.Proto.Trace.span_set_end_time_unix_nano span end_time;

      (* use the current tracer *)
      OTEL.Trace_provider.emit span
    | _ -> ()

  let add_data_to_span _self span (data : (_ * Trace.user_data) list) =
    match span with
    | Span_otel sp -> OTEL.Span.add_attrs sp data
    | _ -> ()

  let severity_of_level : Trace_core.Level.t -> _ = function
    | Trace -> OTEL.Log_record.Severity_number_trace
    | Debug1 -> OTEL.Log_record.Severity_number_debug
    | Debug2 -> OTEL.Log_record.Severity_number_debug2
    | Debug3 -> OTEL.Log_record.Severity_number_debug3
    | Error -> OTEL.Log_record.Severity_number_error
    | Info -> OTEL.Log_record.Severity_number_info
    | Warning -> OTEL.Log_record.Severity_number_warn

  let message () ~(level : Trace_core.Level.t) ~params:_ ~data ~span msg : unit
      =
    let observed_time_unix_nano = OTEL.Clock.now_main () in
    let trace_id, span_id =
      match span with
      | Some (Span_otel sp) ->
        Some (OTEL.Span.trace_id sp), Some (OTEL.Span.id sp)
      | _ ->
        (match Ambient_context.get k_span_ctx with
        | Some sp ->
          Some (OTEL.Span_ctx.trace_id sp), Some (OTEL.Span_ctx.parent_id sp)
        | _ -> None, None)
    in

    let severity = severity_of_level level in
    let log =
      OTEL.Log_record.make ~severity ?trace_id ?span_id ~attrs:data
        ~observed_time_unix_nano (`String msg)
    in
    OTEL.Log_provider.emit log

  let metric () ~level:_ ~params:_ ~data:attrs name v : unit =
    let now = OTEL.Clock.now_main () in
    let kind =
      let open Trace_core.Core_ext in
      match v with
      | Metric_int i -> `gauge (OTEL.Metrics.int ~attrs ~now i)
      | Metric_float v -> `gauge (OTEL.Metrics.float ~attrs ~now v)
      | Metric_sum_int i -> `sum (OTEL.Metrics.int ~attrs ~now i)
      | Metric_sum_float v -> `sum (OTEL.Metrics.float ~attrs ~now v)
      | Metric_hist h -> `hist h
      | _ -> `none
    in

    let m =
      match kind with
      | `none -> []
      | `gauge v -> [ OTEL.Metrics.gauge ~name [ v ] ]
      | `sum v -> [ OTEL.Metrics.sum ~name [ v ] ]
      | `hist h -> [ OTEL.Metrics.histogram ~name [ h ] ]
    in
    if m <> [] then OTEL.Emitter.emit (OTEL.Meter_provider.get ()).emit m

  let extension (_self : state) ~level:_ ev =
    match ev with
    | Ev_link_span (Span_otel sp1, sc2) ->
      OTEL.Span.add_links sp1 [ OTEL.Span_link.of_span_ctx sc2 ]
    | Ev_link_span _ -> ()
    | Ev_set_span_kind (Span_otel sp, k) -> OTEL.Span.set_kind sp k
    | Ev_set_span_kind _ -> ()
    | Ev_set_span_status (Span_otel sp, st) -> OTEL.Span.set_status sp st
    | Ev_set_span_status _ -> ()
    | Ev_record_exn { sp = Span_otel sp; exn; bt } ->
      OTEL.Span.record_exception sp exn bt
    | Ev_record_exn _ -> ()
    | _ -> ()

  let init () = Trace.set_ambient_context_provider ambient_span_provider

  let shutdown () = ()

  let callbacks : state Trace.Collector.Callbacks.t =
    Trace.Collector.Callbacks.make ~enter_span ~exit_span ~add_data_to_span
      ~message ~metric ~extension ~init ~shutdown ()
end

let collector : Trace_core.collector =
  Trace_core.Collector.C_some ((), callbacks)

let with_ambient_span (sp : Trace.span) f =
  match sp with
  | Span_otel sp ->
    Ambient_context.with_key_bound_to k_span_ctx (OTEL.Span.to_span_ctx sp) f
  | _ -> f ()

let with_ambient_span_ctx (sp : OTEL.Span_ctx.t) f =
  Ambient_context.with_key_bound_to k_span_ctx sp f

let link_span_to_otel_ctx (sp1 : Trace.span) (sp2 : OTEL.Span_ctx.t) : unit =
  if Trace.enabled () then Trace.extension_event @@ Ev_link_span (sp1, sp2)

let link_spans (sp1 : Trace.span) (sp2 : Trace.span) : unit =
  if Trace.enabled () then (
    match sp2 with
    | Span_otel sp2 ->
      Trace.extension_event @@ Ev_link_span (sp1, OTEL.Span.to_span_ctx sp2)
    | _ -> ()
  )

let[@inline] set_span_kind sp k : unit =
  if Trace.enabled () then Trace.extension_event @@ Ev_set_span_kind (sp, k)

let[@inline] set_span_status sp status : unit =
  if Trace.enabled () then
    Trace.extension_event @@ Ev_set_span_status (sp, status)

let record_exception sp exn bt : unit =
  if Trace.enabled () then
    Trace.extension_event @@ Ev_record_exn { sp; exn; bt }

let setup () = Trace.setup_collector collector

let setup_with_otel_exporter exp : unit =
  OTEL.Sdk.set exp;
  Trace.setup_collector collector

let setup_with_otel_backend = setup_with_otel_exporter

module Well_known = struct end
