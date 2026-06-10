(** Optional, self-contained OTLP/HTTP sender for a {!Convert.bundle}.

    This is a thin alternative to setting up a full [opentelemetry-client-*]
    exporter: it POSTs the encoded batches directly to a collector. It is only
    functional when the optional [curly] library is available at build time;
    otherwise {!available} is [false] and {!send} returns an error. *)

type protocol =
  | Protobuf
  | Json

val available : bool
(** [true] iff this build was compiled with [curly] support. *)

val send :
  ?endpoint:string ->
  ?protocol:protocol ->
  Convert.bundle ->
  (unit, string) result
(** [send ?endpoint ?protocol bundle] POSTs the bundle's traces to
    [<endpoint>/v1/traces] and metrics to [<endpoint>/v1/metrics].

    @param endpoint
      base collector URL; defaults to [OTEL_EXPORTER_OTLP_ENDPOINT] or
      [http://localhost:4318].
    @param protocol wire format (default {!Protobuf}). *)
