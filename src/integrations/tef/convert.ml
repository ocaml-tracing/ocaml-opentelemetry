(** Pure conversion from parsed TEF events ({!Tef_event.t}) to a bundle of OTEL
    signals (spans + metrics).

    The conversion has no side effects: feeding it events yields a {!bundle} of
    fully-constructed {!Opentelemetry.Span.t} and {!Opentelemetry.Metrics.t}.
    Sending the bundle is a separate step (see {!Emit} and {!Curl_export}). *)

module Span = Opentelemetry.Span
module Trace_id = Opentelemetry.Trace_id
module Span_id = Opentelemetry.Span_id
module Event = Opentelemetry.Event
module Metrics = Opentelemetry.Metrics

type bundle = {
  spans: Span.t list;
  metrics: Metrics.t list;
  service_name: string option;
}

(** Convert a microsecond timestamp to unix-nanoseconds, plus an optional base
    offset (an escape hatch for traces recorded against a monotonic clock). *)
let to_ns ~base_ns (ts_us : float) : int64 =
  Int64.add base_ns (Int64.of_float (ts_us *. 1000.))

type open_span = {
  trace_id: Trace_id.t;
  span_id: Span_id.t;
  parent: Span_id.t option;
  pid: int;
  tid: int;
  name: string;
  start_ns: int64;
  default_end_ns: int64; (* used for sync spans and as a fallback *)
  attrs: (string * Opentelemetry.Value.t) list;
  mutable events: Event.t list; (* accumulated instant events, reversed *)
}
(** An in-flight span, finished (turned into a real span) when it closes. *)

let dur_of (e : Tef_event.t) : float =
  match e.phase with
  | Tef_event.X { dur } -> dur
  | _ -> 0.

(** Chronological order: by start time ascending; on ties, longer (containing)
    spans come first so they end up as parents. *)
let sort_events (l : Tef_event.t list) : Tef_event.t list =
  List.stable_sort
    (fun (a : Tef_event.t) (b : Tef_event.t) ->
      let c = compare a.ts b.ts in
      if c <> 0 then
        c
      else
        compare (dur_of b) (dur_of a))
    l

let of_events ?service_name ?(base_ns = 0L) (events : Tef_event.t list) : bundle
    =
  (* first: collect process/thread names (metadata events carry no ts and may
     appear anywhere, so gather them up-front). *)
  let process_names : (int, string) Hashtbl.t = Hashtbl.create 8 in
  let thread_names : (int * int, string) Hashtbl.t = Hashtbl.create 8 in
  let first_process_name = ref None in
  List.iter
    (fun (e : Tef_event.t) ->
      match e.phase with
      | Tef_event.Meta_process_name n ->
        if n <> "" then (
          if not (Hashtbl.mem process_names e.pid) then
            if !first_process_name = None then first_process_name := Some n;
          Hashtbl.replace process_names e.pid n
        )
      | Tef_event.Meta_thread_name n ->
        if n <> "" then Hashtbl.replace thread_names (e.pid, e.tid) n
      | _ -> ())
    events;

  let service_name =
    match service_name with
    | Some _ as s -> s
    | None -> !first_process_name
  in

  (* Attributes derived from pid/tid metadata, attached to every span. *)
  let thread_attrs pid tid : (string * Opentelemetry.Value.t) list =
    let base = [ "process.pid", `Int pid; "thread.id", `Int tid ] in
    match Hashtbl.find_opt thread_names (pid, tid) with
    | Some n -> ("thread.name", `String n) :: base
    | None -> base
  in

  let spans = ref [] in
  let build_span ?(extra_attrs = []) (os : open_span) ~end_ns : unit =
    let attrs = os.attrs @ extra_attrs @ thread_attrs os.pid os.tid in
    let span =
      Span.make ~kind:Opentelemetry.Span.Span_kind_internal
        ~trace_id:os.trace_id ~id:os.span_id ?parent:os.parent ~attrs
        ~events:(List.rev os.events) ~start_time:os.start_ns ~end_time:end_ns
        os.name
    in
    spans := span :: !spans
  in

  (* Sync "X" spans: a containment stack per (pid,tid). *)
  let sync_stacks : (int * int, open_span list ref) Hashtbl.t =
    Hashtbl.create 8
  in
  let sync_stack key =
    match Hashtbl.find_opt sync_stacks key with
    | Some s -> s
    | None ->
      let s = ref [] in
      Hashtbl.add sync_stacks key s;
      s
  in
  (* Close any sync span on [key]'s stack that has ended by time [t_ns]. *)
  let pop_ended key ~t_ns =
    let st = sync_stack key in
    let rec loop () =
      match !st with
      | os :: rest when os.default_end_ns <= t_ns ->
        st := rest;
        build_span os ~end_ns:os.default_end_ns;
        loop ()
      | _ -> ()
    in
    loop ()
  in

  (* Async "b"/"e" spans: a stack per (pid,tid,id). *)
  let async_stacks : (int * int * int, open_span list ref) Hashtbl.t =
    Hashtbl.create 8
  in
  let async_stack key =
    match Hashtbl.find_opt async_stacks key with
    | Some s -> s
    | None ->
      let s = ref [] in
      Hashtbl.add async_stacks key s;
      s
  in

  (* Find the innermost currently-open span for (pid,tid), to attach instants. *)
  let innermost_open pid tid : open_span option =
    match !(sync_stack (pid, tid)) with
    | os :: _ -> Some os
    | [] ->
      (* otherwise pick the most-recently-started open async span on this thread *)
      Hashtbl.fold
        (fun (p, t, _) st acc ->
          if p = pid && t = tid then (
            match !st with
            | os :: _ ->
              (match acc with
              | Some prev when prev.start_ns >= os.start_ns -> acc
              | _ -> Some os)
            | [] -> acc
          ) else
            acc)
        async_stacks None
  in

  (* Counters: group data points by metric name, preserving first-seen order. *)
  let counter_dps :
      (string, Opentelemetry.Proto.Metrics.number_data_point list ref) Hashtbl.t
      =
    Hashtbl.create 8
  in
  let counter_order = ref [] in
  let add_counter ~t_ns ~attrs name (v : Opentelemetry.Value.t) =
    let dp_opt =
      match v with
      | `Int i -> Some (Metrics.int ~now:t_ns ~attrs i)
      | `Float f -> Some (Metrics.float ~now:t_ns ~attrs f)
      | `Bool b ->
        Some
          (Metrics.int ~now:t_ns ~attrs
             (if b then
                1
              else
                0))
      | _ -> None
    in
    match dp_opt with
    | None -> ()
    | Some dp ->
      let r =
        match Hashtbl.find_opt counter_dps name with
        | Some r -> r
        | None ->
          let r = ref [] in
          Hashtbl.add counter_dps name r;
          counter_order := name :: !counter_order;
          r
      in
      r := dp :: !r
  in

  let max_ts_ns = ref base_ns in

  (* Pass 2: chronological processing. *)
  List.iter
    (fun (e : Tef_event.t) ->
      let t_ns = to_ns ~base_ns e.ts in
      if t_ns > !max_ts_ns then max_ts_ns := t_ns;
      match e.phase with
      | Tef_event.X { dur } ->
        let key = e.pid, e.tid in
        pop_ended key ~t_ns;
        let st = sync_stack key in
        let parent, trace_id =
          match !st with
          | top :: _ -> Some top.span_id, top.trace_id
          | [] -> None, Trace_id.create ()
        in
        let os =
          {
            trace_id;
            span_id = Span_id.create ();
            parent;
            pid = e.pid;
            tid = e.tid;
            name = e.name;
            start_ns = t_ns;
            default_end_ns = to_ns ~base_ns (e.ts +. dur);
            attrs = e.args;
            events = [];
          }
        in
        st := os :: !st
      | Tef_event.Begin { id } ->
        let key = e.pid, e.tid, id in
        let st = async_stack key in
        let parent, trace_id =
          match !st with
          | top :: _ -> Some top.span_id, top.trace_id
          | [] -> None, Trace_id.create ()
        in
        let os =
          {
            trace_id;
            span_id = Span_id.create ();
            parent;
            pid = e.pid;
            tid = e.tid;
            name = e.name;
            start_ns = t_ns;
            default_end_ns = t_ns;
            attrs = e.args;
            events = [];
          }
        in
        st := os :: !st
      | Tef_event.End { id } ->
        let key = e.pid, e.tid, id in
        let st = async_stack key in
        (match !st with
        | os :: rest ->
          st := rest;
          build_span os ~end_ns:t_ns ~extra_attrs:e.args
        | [] -> () (* unmatched end: ignore *))
      | Tef_event.Instant ->
        (match innermost_open e.pid e.tid with
        | Some os ->
          os.events <-
            Event.make ~time_unix_nano:t_ns ~attrs:e.args e.name :: os.events
        | None ->
          (* nothing open: a standalone zero-duration span carrying the event *)
          let os =
            {
              trace_id = Trace_id.create ();
              span_id = Span_id.create ();
              parent = None;
              pid = e.pid;
              tid = e.tid;
              name = e.name;
              start_ns = t_ns;
              default_end_ns = t_ns;
              attrs = e.args;
              events = [ Event.make ~time_unix_nano:t_ns ~attrs:e.args e.name ];
            }
          in
          build_span os ~end_ns:t_ns)
      | Tef_event.Counter ->
        let attrs = [ "process.pid", `Int e.pid; "thread.id", `Int e.tid ] in
        List.iter (fun (k, v) -> add_counter ~t_ns ~attrs k v) e.args
      | Tef_event.Meta_process_name _ | Tef_event.Meta_thread_name _
      | Tef_event.Meta_other ->
        ())
    (sort_events events);

  (* Flush remaining open spans. *)
  Hashtbl.iter
    (fun _ st ->
      List.iter (fun os -> build_span os ~end_ns:os.default_end_ns) !st)
    sync_stacks;
  Hashtbl.iter
    (fun _ st ->
      List.iter
        (fun os ->
          let end_ns =
            if !max_ts_ns > os.start_ns then
              !max_ts_ns
            else
              os.start_ns
          in
          build_span os ~end_ns)
        !st)
    async_stacks;

  let metrics =
    List.rev_map
      (fun name ->
        let dps = List.rev !(Hashtbl.find counter_dps name) in
        Metrics.gauge ~name dps)
      !counter_order
  in
  { spans = List.rev !spans; metrics; service_name }
