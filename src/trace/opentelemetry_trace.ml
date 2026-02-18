module Otel = Opentelemetry
module Otrace = Trace_core (* ocaml-trace *)
module TLS = Thread_local_storage

open struct
  let spf = Printf.sprintf
end

module Well_known = struct end

let on_internal_error =
  ref (fun msg -> Printf.eprintf "error in Opentelemetry_trace: %s\n%!" msg)

module Span_info = struct
  type t = {
    start_time: int64;
    name: string;
    scope: Otel.Scope.t;
    parent: Otel.Span_ctx.t option;
  }
end

type Otrace.span += Span_otel of Span_info.t

type Otrace.extension_event +=
  | Ev_link_span of Otrace.span * Otrace.span
  | Ev_set_span_kind of Otrace.span * Otel.Span_kind.t
  | Ev_record_exn of Otrace.span * exn * Printexc.raw_backtrace

module Internal = struct
  let enter_span' ?(parent_span : Otrace.span option) ~__FUNCTION__ ~__FILE__
      ~__LINE__ ~data name : Span_info.t =
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

    { Span_info.start_time; name; scope = new_scope; parent }

  let exit_span_ ({ name; start_time; scope; parent } : Span_info.t) :
      Otel.Span.t =
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
      ~parent name : Otrace.span =
    let parent_span =
      match parent with
      | Otrace.P_some sp -> Some sp
      | _ -> None
    in
    let span_info =
      enter_span' ?parent_span ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data name
    in
    Span_otel span_info

  let exit_span _st (span : Otrace.span) =
    match span with
    | Span_otel span_info ->
      let otel_span = exit_span_ span_info in
      Otel.Trace.emit [ otel_span ]
    | _ -> ()

  let add_data_to_span _st (span : Otrace.span) data =
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
    let open Otrace.Core_ext in
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

  let callbacks : unit Otrace.Collector.Callbacks.t =
    Otrace.Collector.Callbacks.make ~enter_span ~exit_span ~add_data_to_span
      ~message ~metric ~extension ()
end

let link_spans (sp1 : Otrace.span) (sp2 : Otrace.span) : unit =
  if Otrace.enabled () then Otrace.extension_event @@ Ev_link_span (sp1, sp2)

let set_span_kind sp k : unit =
  if Otrace.enabled () then Otrace.extension_event @@ Ev_set_span_kind (sp, k)

let record_exception sp exn bt : unit =
  if Otrace.enabled () then Otrace.extension_event @@ Ev_record_exn (sp, exn, bt)

let with_ambient_span (sp : Otrace.span) f =
  match sp with
  | Span_otel sb -> Otel.Scope.with_ambient_scope sb.scope f
  | _ -> f ()

let collector () : Otrace.collector =
  Trace_core.Collector.C_some ((), Internal.callbacks)

let setup () = Otrace.setup_collector @@ collector ()

let setup_with_otel_backend b : unit =
  Otel.Collector.set_backend b;
  setup ()
