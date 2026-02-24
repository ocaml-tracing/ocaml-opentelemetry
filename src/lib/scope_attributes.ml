(** Helper for building instrumentation scope attributes.

    Used internally by {!Tracer.get}, {!Meter.get}, {!Logger.get}. *)

(** Build a list of fixed key-value attributes from instrumentation scope
    parameters. These attributes will be injected into every signal emitted by a
    tracer/meter/logger obtained via the corresponding [get] function.

    @param name instrumentation scope name (recorded as [otel.scope.name])
    @param version
      instrumentation scope version (recorded as [otel.scope.version])
    @param __MODULE__
      the OCaml module name, typically the [__MODULE__] literal (recorded as
      [code.namespace])
    @param attrs additional fixed attributes *)
let make_attrs ?name ?version ?(attrs : (string * [< Value.t ]) list = [])
    ?__MODULE__ () : Key_value.t list =
  let maybe_cons opt k l =
    match opt with
    | None -> l
    | Some v -> (k, (`String v : Value.t)) :: l
  in
  let l = (attrs :> Key_value.t list) in
  let l = maybe_cons __MODULE__ Conventions.Attributes.Code.namespace l in
  let l = maybe_cons version "otel.scope.version" l in
  let l = maybe_cons name "otel.scope.name" l in
  l
