module Otel = Opentelemetry
module Trace = Trace_core (* ocaml-trace *)

module Well_known = struct end

let on_internal_error =
  ref (fun msg -> Printf.eprintf "error in Opentelemetry_trace: %s\n%!" msg)

module Extensions = struct
  type span_info = {
    start_time: int64;
    name: string;
    scope: Otel.Scope.t;
    parent: Otel.Span_ctx.t option;
  }

  let k_span_info : span_info Hmap.key = Hmap.Key.create ()

  let[@inline] scope_of_span_info s = s.scope

  let[@inline] span_info_of_scope_exn (scope : Otel.Scope.t) : span_info =
    try Hmap.get k_span_info scope.hmap
    with Invalid_argument _ -> assert false

  type Trace.span += Span_otel of span_info

  type Trace.extension_event +=
    | Ev_link_span of Trace.span * Trace.span
    | Ev_record_exn of Trace.span * exn * Printexc.raw_backtrace
    | Ev_set_span_kind of Trace.span * Otel.Span_kind.t

  type Trace.metric +=
    | Metric_hist of Opentelemetry_proto.Metrics.histogram_data_point
    | Metric_sum_int of int
    | Metric_sum_float of float
end

open Extensions

module Collector_ = struct
  let enter_span' ?(parent_span : Trace.span option) ~__FUNCTION__ ~__FILE__
      ~__LINE__ ~data name : span_info =
    let open Otel in
    let span_id = Span_id.create () in

    let parent_scope = Scope.get_ambient_scope () in
    let trace_id =
      match parent_scope with
      | Some sc -> sc.trace_id
      | None -> Trace_id.create ()
    in
    let parent =
      match parent_span, parent_scope with
      | Some (Span_otel parent_span), _ ->
        Some (Otel.Scope.to_span_ctx parent_span.scope)
      | _, Some sc -> Some (Otel.Scope.to_span_ctx sc)
      | _, None -> None
    in

    let new_scope = Otel.Scope.make ~trace_id ~span_id ~attrs:data () in
    let start_time = Timestamp_ns.now_unix_ns () in

    let attrs_function =
      match __FUNCTION__ with
      | None -> []
      | Some __FUNCTION__ ->
        (try
           let last_dot = String.rindex __FUNCTION__ '.' in
           let module_path = String.sub __FUNCTION__ 0 last_dot in
           let function_name =
             String.sub __FUNCTION__ (last_dot + 1)
               (String.length __FUNCTION__ - last_dot - 1)
           in
           [
             "code.function", `String function_name;
             "code.namespace", `String module_path;
           ]
         with Not_found -> [])
    in

    (* directly store file, line, etc in scope *)
    Otel.Scope.add_attrs new_scope (fun () ->
        ("code.filepath", `String __FILE__)
        :: ("code.lineno", `Int __LINE__)
        :: attrs_function);

    let span_info = { start_time; name; scope = new_scope; parent } in
    Otel.Scope.hmap_set k_span_info span_info new_scope;
    span_info

  let exit_span_ ({ name; start_time; scope; parent } : span_info) : Otel.Span.t
      =
    let open Otel in
    let end_time = Timestamp_ns.now_unix_ns () in
    let attrs = Scope.attrs scope in
    let parent_id = Option.map Span_ctx.parent_id parent in
    let kind = Scope.kind scope in
    let status = Scope.status scope in

    Span.create ?kind ~trace_id:scope.trace_id ?parent:parent_id ?status
      ~id:scope.span_id ~start_time ~end_time ~attrs
      ~events:(Scope.events scope) ~links:(Scope.links scope) name
    |> fst

  let enter_span _st ~__FUNCTION__ ~__FILE__ ~__LINE__ ~level:_ ~params:_ ~data
      ~parent name : Trace.span =
    let parent_span =
      match parent with
      | Trace.P_some sp -> Some sp
      | _ -> None
    in
    let span_info =
      enter_span' ?parent_span ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data name
    in
    Span_otel span_info

  let exit_span _st (span : Trace.span) =
    match span with
    | Span_otel span_info ->
      let otel_span = exit_span_ span_info in
      Otel.Trace.emit [ otel_span ]
    | _ -> ()

  let add_data_to_span _st (span : Trace.span) data =
    match span with
    | Span_otel span_info ->
      Otel.Scope.add_attrs span_info.scope (fun () -> data)
    | _ -> ()

  let message _st ~level:_ ~params:_ ~data:_ ~span msg : unit =
    let trace_id, span_id =
      match span with
      | Some (Span_otel si) -> Some si.scope.trace_id, Some si.scope.span_id
      | _ ->
        (match Otel.Scope.get_ambient_scope () with
        | None -> None, None
        | Some scope -> Some scope.trace_id, Some scope.span_id)
    in

    let log = Otel.Logs.make_str ?trace_id ?span_id msg in
    Otel.Logs.emit [ log ]

  let metric _st ~level:_ ~params:_ ~data:attrs name v =
    let open Trace.Core_ext in
    match v with
    | Metric_int i ->
      let m = Otel.Metrics.(gauge ~name [ int ~attrs i ]) in
      Otel.Metrics.emit [ m ]
    | Metric_float f ->
      let m = Otel.Metrics.(gauge ~name [ float ~attrs f ]) in
      Otel.Metrics.emit [ m ]
    | _ -> ()

  let extension _st ~level:_ ev =
    match ev with
    | Ev_link_span (Span_otel sb1, Span_otel sb2) ->
      Otel.Scope.add_links sb1.scope (fun () ->
          [ Otel.Scope.to_span_link sb2.scope ])
    | Ev_set_span_kind (Span_otel sb, k) -> Otel.Scope.set_kind sb.scope k
    | Ev_record_exn (Span_otel sb, exn, bt) ->
      Otel.Scope.record_exception sb.scope exn bt
    | _ -> ()

  let callbacks : unit Trace.Collector.Callbacks.t =
    Trace.Collector.Callbacks.make ~enter_span ~exit_span ~add_data_to_span
      ~message ~metric ~extension ()
end

module Ambient_span_provider_ = struct
  let get_current_span () =
    match Otel.Scope.get_ambient_scope () with
    | None -> None
    | Some scope -> Some (Span_otel (span_info_of_scope_exn scope))

  let with_current_span_set_to () span f =
    match span with
    | Span_otel span_info ->
      Otel.Scope.with_ambient_scope (scope_of_span_info span_info) (fun () ->
          f span)
    | _ -> f span

  let callbacks : unit Trace.Ambient_span_provider.Callbacks.t =
    { get_current_span; with_current_span_set_to }

  let provider = Trace.Ambient_span_provider.ASP_some ((), callbacks)
end

let link_spans (sp1 : Trace.span) (sp2 : Trace.span) : unit =
  if Trace.enabled () then Trace.extension_event @@ Ev_link_span (sp1, sp2)

let set_span_kind sp k : unit =
  if Trace.enabled () then Trace.extension_event @@ Ev_set_span_kind (sp, k)

let record_exception sp exn bt : unit =
  if Trace.enabled () then Trace.extension_event @@ Ev_record_exn (sp, exn, bt)

let with_ambient_span (sp : Trace.span) f =
  match sp with
  | Span_otel sb -> Otel.Scope.with_ambient_scope sb.scope f
  | _ -> f ()

let ambient_span_provider = Ambient_span_provider_.provider

let collector () : Trace.collector =
  Trace_core.Collector.C_some ((), Collector_.callbacks)

let setup () =
  Trace.set_ambient_context_provider Ambient_span_provider_.provider;
  Trace.setup_collector @@ collector ()

let setup_with_otel_backend b : unit =
  Otel.Collector.set_backend b;
  setup ()
