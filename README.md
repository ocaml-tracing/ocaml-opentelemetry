
# Opentelemetry [![build](https://github.com/imandra-ai/ocaml-opentelemetry/actions/workflows/main.yml/badge.svg)](https://github.com/imandra-ai/ocaml-opentelemetry/actions/workflows/main.yml)

This project provides an API for instrumenting server software
using [opentelemetry](https://opentelemetry.io/docs), as well as
connectors to talk to opentelemetry software such as [jaeger](https://www.jaegertracing.io/).

- library `opentelemetry` should be used to instrument your code
  and possibly libraries. It doesn't communicate with anything except
  an exporter (default: no-op);
- library `opentelemetry-client-ocurl` is an exporter that communicates
  via http+protobuf with some collector (otelcol, datadog-agent, etc.) using cURL bindings;
- library `opentelemetry-client-cohttp-lwt` is an exporter that communicates
  via http+protobuf with some collector using cohttp.

## License

MIT

## Features

- [x] basic traces
- [x] basic metrics
- [x] basic logs
- [ ] nice API
- [x] interface with `lwt`
- [x] sync collector relying on ocurl
  * [x] batching, perf, etc.
- [ ] async collector relying on ocurl-multi
- [ ] interface with `logs` (carry context around)
- [x] implicit scope (via vendored `ambient-context`, see `opentelemetry.ambient-context`)

## Use

For now, instrument traces/spans, logs, and metrics manually:

```ocaml
module Otel = Opentelemetry
let (let@) = (@@)

let foo () =
  let@ span = Otel.Tracer.with_ "foo"
      ~attrs:["hello", `String "world"] in
  do_work ();
  let now = Otel.Clock.now Otel.Meter.default.clock in
  Otel.Meter.emit1 Otel.Meter.default
    Otel.Metrics.(gauge ~name:"foo.x" [int ~now 42]);
  Otel.Span.add_event span (Otel.Event.make "work done");
  do_more_work ();
  ()
```

### Setup

If you're writing a top-level application, you need to perform some initial configuration.

1. Set the [`service_name`][];
2. optionally configure [ambient-context][] with the appropriate storage for your environment — TLS, Lwt, Eio…;
3. and install an exporter (usually by calling your client library's `with_setup` function.)

For example, if your application is using Lwt, and you're using `ocurl` as your collector, you might do something like this:

```ocaml
let main () =
  Otel.Globals.service_name := "my_service";
  Otel.Gc_metrics.setup ();

  Opentelemetry_ambient_context.set_storage_provider (Opentelemetry_ambient_context_lwt.storage ());
  Opentelemetry_client_ocurl.with_setup () @@ fun () ->
  (* … *)
  foo ();
  (* … *)
```

  [`service_name`]: <https://v3.ocaml.org/p/opentelemetry/latest/doc/Opentelemetry/Globals/index.html#val-service_name>
  [ambient-context]: now vendored as `opentelemetry.ambient-context`, formerly <https://v3.ocaml.org/p/ambient-context>

## Migration v012 → v0.13

see `doc/migration_guide_v0.13.md`

## Configuration

### Environment Variables

The library supports standard OpenTelemetry environment variables:

**General:**
- `OTEL_SDK_DISABLED` - disable the SDK (default: false)
- `OTEL_SERVICE_NAME` - service name
- `OTEL_RESOURCE_ATTRIBUTES` - comma-separated key=value resource attributes
- `OTEL_OCAML_DEBUG=1` - print debug messages from the opentelemetry library

**Exporter endpoints:**
- `OTEL_EXPORTER_OTLP_ENDPOINT` - base endpoint (default: http://localhost:4318)
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` - traces endpoint
- `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` - metrics endpoint
- `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` - logs endpoint

**Exporter configuration:**
- `OTEL_EXPORTER_OTLP_PROTOCOL` - protocol: http/protobuf or http/json (default: http/protobuf)

**Headers:**
- `OTEL_EXPORTER_OTLP_HEADERS` - headers as comma-separated key=value pairs
- `OTEL_EXPORTER_OTLP_TRACES_HEADERS` - traces-specific headers
- `OTEL_EXPORTER_OTLP_METRICS_HEADERS` - metrics-specific headers
- `OTEL_EXPORTER_OTLP_LOGS_HEADERS` - logs-specific headers


## opentelemetry-client-ocurl

This is a synchronous exporter that uses the http+protobuf format
to send signals (metrics, traces, logs) to some collector (eg. `otelcol`
or the datadog agent).

Do note that it uses a thread pool and is incompatible
with uses of `fork` on some Unixy systems.
See [#68](https://github.com/imandra-ai/ocaml-opentelemetry/issues/68) for a possible workaround.

## opentelemetry-client-cohttp-lwt

This is a Lwt-friendly exporter that uses cohttp to send
signals to some collector (e.g. `otelcol`). It must be run
inside a `Lwt_main.run` scope.

## Opentelemetry-trace

The optional library `opentelemetry.trace`, present if [trace](https://github.com/c-cube/trace) is
installed, provides a collector for `trace`. This collector forwards and translates
events from `trace` into `opentelemetry`. It's only useful if there also is also a OTEL collector.

## License

MIT

## Semantic Conventions

Not supported yet.

- [ ] [metrics](https://opentelemetry.io/docs/reference/specification/metrics/semantic_conventions/)
- [ ] [traces](https://opentelemetry.io/docs/reference/specification/trace/semantic_conventions/)
- [ ] [resources](https://opentelemetry.io/docs/reference/specification/resource/semantic_conventions/)
