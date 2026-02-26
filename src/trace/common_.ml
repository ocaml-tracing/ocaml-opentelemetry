module OTEL = Opentelemetry
module Trace = Trace_core (* ocaml-trace *)
module Ambient_context = Ambient_context

let ( let@ ) = ( @@ )

let spf = Printf.sprintf
