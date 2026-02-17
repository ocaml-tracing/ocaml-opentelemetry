open Common_
open Proto.Trace

type t = span

type id = Span_id.t

type kind = Span_kind.t =
  | Span_kind_unspecified
  | Span_kind_internal
  | Span_kind_server
  | Span_kind_client
  | Span_kind_producer
  | Span_kind_consumer

type key_value =
  string
  * [ `Int of int
    | `String of string
    | `Bool of bool
    | `Float of float
    | `None
    ]

let[@inline] id self = Span_id.of_bytes self.span_id

let[@inline] trace_id self = Trace_id.of_bytes self.trace_id

let[@inline] is_not_dummy self = Span_id.is_valid (id self)

let pp = Proto.Trace.pp_span

let default_kind = ref Proto.Trace.Span_kind_unspecified

let make ?(kind = !default_kind) ?trace_state ?(attrs = []) ?(events = [])
    ?status ~trace_id ~id ?parent ?(links = []) ~start_time ~end_time name : t =
  let trace_id = Trace_id.to_bytes trace_id in
  let parent_span_id = Option.map Span_id.to_bytes parent in
  let attributes = List.map Key_value.conv attrs in
  let span =
    make_span ~trace_id ?parent_span_id ~span_id:(Span_id.to_bytes id)
      ~attributes ~events ?trace_state ?status ~kind ~name ~links
      ~start_time_unix_nano:start_time ~end_time_unix_nano:end_time ()
  in
  span

let dummy : t =
  Proto.Trace.make_span
    ~trace_id:Trace_id.(dummy |> to_bytes)
    ~span_id:Span_id.(dummy |> to_bytes)
    ()

let create_new ?kind ?(id = Span_id.create ()) ?trace_state ?attrs ?events
    ?status ~trace_id ?parent ?links ~start_time ~end_time name : t =
  make ?kind ~id ~trace_id ?trace_state ?attrs ?events ?status ?parent ?links
    ~start_time ~end_time name

let attrs self = self.attributes |> List.rev_map Key_value.of_otel

let events self = self.events

let links self : Span_link.t list = self.links

let status self = self.status

let kind self =
  let k = self.kind in
  if k = Span_kind_unspecified then
    None
  else
    Some k

let to_span_link (self : t) : Span_link.t =
  make_span_link ~attributes:self.attributes
    ?flags:
      (if span_has_flags self then
         Some self.flags
       else
         None)
    ?dropped_attributes_count:
      (if span_has_dropped_attributes_count self then
         Some self.dropped_attributes_count
       else
         None)
    ?trace_state:
      (if span_has_trace_state self then
         Some self.trace_state
       else
         None)
    ~trace_id:self.trace_id ~span_id:self.span_id ()

let[@inline] to_span_ctx (self : t) : Span_ctx.t =
  Span_ctx.make ~trace_id:(trace_id self) ~parent_id:(id self) ()

(* Note: a span must not be concurrently modified from multiple
   threads or domains. *)
let[@inline] add_event self ev : unit =
  if is_not_dummy self then span_set_events self (ev :: self.events)

let add_event' self ev : unit =
  if is_not_dummy self then span_set_events self (ev () :: self.events)

let record_exception (self : t) (exn : exn) (bt : Printexc.raw_backtrace) : unit
    =
  if is_not_dummy self then (
    let ev =
      Event.make "exception"
        ~attrs:
          [
            "exception.message", `String (Printexc.to_string exn);
            "exception.type", `String (Printexc.exn_slot_name exn);
            ( "exception.stacktrace",
              `String (Printexc.raw_backtrace_to_string bt) );
          ]
    in
    add_event self ev
  )

let add_attrs (self : t) (attrs : Key_value.t list) : unit =
  if is_not_dummy self then (
    let attrs = List.rev_map Key_value.conv attrs in
    let attrs = List.rev_append attrs self.attributes in
    span_set_attributes self attrs
  )

let add_attrs' (self : t) (attrs : unit -> Key_value.t list) : unit =
  if is_not_dummy self then (
    let attrs = List.rev_map Key_value.conv (attrs ()) in
    let attrs = List.rev_append attrs self.attributes in
    span_set_attributes self attrs
  )

let add_links (self : t) (links : Span_link.t list) : unit =
  if is_not_dummy self && links <> [] then (
    let links = List.rev_append links self.links in
    span_set_links self links
  )

let add_links' (self : t) (links : unit -> Span_link.t list) : unit =
  if is_not_dummy self then (
    let links = List.rev_append (links ()) self.links in
    span_set_links self links
  )

let set_status = span_set_status

let set_kind = span_set_kind

let k_ambient : t Context.key = Context.new_key ()
