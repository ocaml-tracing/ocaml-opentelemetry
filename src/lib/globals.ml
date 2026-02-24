(** Process-wide metadata, environment variables, etc. *)

open Common_
open Proto.Common

(** Main service name metadata *)
let service_name =
  ref
    (match Sys.getenv_opt "OTEL_SERVICE_NAME" with
    | Some name -> name
    | None -> "unknown_service")

(** Namespace for the service *)
let service_namespace = ref None

(** Unique identifier for the service *)
let service_instance_id = ref None

(** Version for the service
    @since 0.12 *)
let service_version = ref None

let instrumentation_library =
  make_instrumentation_scope ~version:"%%VERSION_NUM%%" ~name:"ocaml-otel" ()

(** Global attributes, initially set via OTEL_RESOURCE_ATTRIBUTES and modifiable
    by the user code. They will be attached to each outgoing metrics/traces. *)
let global_attributes : key_value list ref =
  let parse_pair s =
    match String.split_on_char '=' s with
    | [ a; b ] -> make_key_value ~key:a ~value:(String_value b) ()
    | _ -> failwith (Printf.sprintf "invalid attribute: %S" s)
  in
  ref
  @@
  try
    Sys.getenv "OTEL_RESOURCE_ATTRIBUTES"
    |> String.split_on_char ',' |> List.map parse_pair
  with _ -> []

(** Add a global attribute *)
let add_global_attribute (key : string) (v : Value.t) : unit =
  global_attributes := Key_value.conv (key, v) :: !global_attributes

(* add global attributes to this list *)
let merge_global_attributes_ into : _ list =
  let not_redundant kv = List.for_all (fun kv' -> kv.key <> kv'.key) into in
  List.rev_append (List.filter not_redundant !global_attributes) into

let default_span_kind = Span.default_kind

open struct
  let runtime_attributes =
    Conventions.Attributes.
      [
        Process.Runtime.name, `String "ocaml";
        Process.Runtime.version, `String Sys.ocaml_version;
      ]

  let runtime_attributes_converted = List.map Key_value.conv runtime_attributes
end

(** Attributes about the OCaml runtime. See
    https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/resource/semantic_conventions/process.md#process-runtimes
*)
let[@inline] get_runtime_attributes () = runtime_attributes

let mk_attributes ?(service_name = !service_name) ?(attrs = []) () : _ list =
  let l = List.rev_map Key_value.conv attrs in
  let l = List.rev_append runtime_attributes_converted l in
  let l =
    make_key_value ~key:Conventions.Attributes.Service.name
      ~value:(String_value service_name) ()
    :: l
  in
  let l =
    match !service_instance_id with
    | None -> l
    | Some v ->
      make_key_value ~key:Conventions.Attributes.Service.instance_id
        ~value:(String_value v) ()
      :: l
  in
  let l =
    match !service_namespace with
    | None -> l
    | Some v ->
      make_key_value ~key:Conventions.Attributes.Service.namespace
        ~value:(String_value v) ()
      :: l
  in
  let l =
    match !service_version with
    | None -> l
    | Some v ->
      make_key_value ~key:Conventions.Attributes.Service.version
        ~value:(String_value v) ()
      :: l
  in
  l |> merge_global_attributes_

(** Global tick callback registry. Callbacks are run periodically by the SDK
    ticker. Other modules register here to avoid depending on {!Sdk}. *)
let tick_cbs_ : (unit -> unit) Alist.t = Alist.make ()

let add_on_tick_callback (f : unit -> unit) : unit = Alist.add tick_cbs_ f

let run_tick_callbacks () : unit =
  List.iter (fun f -> f ()) (Alist.get tick_cbs_)

(* TODO: rename to dynamic_attributes *)
module Enricher = struct
  type t = unit -> key_value list

  let cached ~(timeout_s : float) (e : t) : t =
    let last_updated = ref (Unix.gettimeofday ()) in
    let value = ref (e ()) in
    fun () ->
      let now = Unix.gettimeofday () in
      if now > !last_updated +. timeout_s then (
        last_updated := now;
        value := e ()
      );
      !value

  let all_ : t list ref = ref []

  let add f = all_ := f :: !all_
end
