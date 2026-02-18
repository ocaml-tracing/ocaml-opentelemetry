
# Opentelemetry [![build](https://github.com/ocaml-tracing/ocaml-opentelemetry/actions/workflows/main.yml/badge.svg)](https://github.com/ocaml-tracing/ocaml-opentelemetry/actions/workflows/main.yml)

This project provides an API for instrumenting server software
using [opentelemetry](https://opentelemetry.io/docs), as well as
connectors to talk to opentelemetry software such as [jaeger](https://www.jaegertracing.io/).

- library `opentelemetry` should be used to instrument your code
  and possibly libraries. It doesn't communicate with anything except
  a backend (default: dummy backend);
- library `opentelemetry-client-ocurl` is a backend that communicates
  via http+protobuf with some collector (otelcol, datadog-agent, etc.) using cURL bindings;
- library `opentelemetry-client-cohttp-lwt` is a backend that communicates
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
- [x] implicit scope (via [`ambient-context`](https://github.com/ocaml-tracing/ambient-context))

## Use

For now, instrument traces/spans, logs, and metrics manually:

```ocaml
module Otel = Opentelemetry
let (let@) = (@@)

let foo () =
  let@ scope = Otel.Trace.with_  "foo"
      ~attrs:["hello", `String "world"] in
  do_work();
  Otel.Metrics.(
    emit [
      gauge ~name:"foo.x" [int 42];
    ]);
  do_more_work();
  ()
```

### Setup

If you're writing a top-level application, you need to perform some initial configuration.

1. Set the [`service_name`][];
2. optionally configure [ambient-context][] with the appropriate storage for your environment — TLS, Lwt, Eio…;
3. and install a [`Collector`][] (usually by calling your collector's `with_setup` function.)

For example, if your application is using Lwt, and you're using `ocurl` as your collector, you might do something like this:

```ocaml
let main () =
  Otel.Globals.service_name := "my_service";
  Otel.GC_metrics.basic_setup();

  (* install Lwt's fiber-local storage as the ambient context backend *)
  Ambient_context.set_current_storage Ambient_context_lwt.storage;
  Opentelemetry_client_ocurl.with_setup () @@ fun () ->
  (* … *)
  foo ();
  (* … *)
```

  [`service_name`]: <https://github.com/ocaml-tracing/ocaml-opentelemetry>
  [`Collector`]: <https://github.com/ocaml-tracing/ocaml-opentelemetry>
  [ambient-context]: <https://github.com/ocaml-tracing/ambient-context>

## Configuration

The library is configurable via `Opentelemetry.Config`, via the standard
opentelemetry env variables, or with some custom environment variables.

- `OTEL_EXPORTER_OTLP_ENDPOINT` sets the http endpoint to send signals to
- `OTEL_OCAML_DEBUG=1` to print some debug messages from the opentelemetry library ide
- `OTEL_RESOURCE_ATTRIBUTES` sets a comma separated list of custom resource attributes

## Collector opentelemetry-client-ocurl

This is a synchronous collector that uses the http+protobuf format
to send signals (metrics, traces, logs) to some other collector (eg. `otelcol`
or the datadog agent).

Do note that this backend uses a thread pool and is incompatible
with uses of `fork` on some Unixy systems.
See [#68](https://github.com/ocaml-tracing/ocaml-opentelemetry/issues/68) for a possible workaround.

## Collector opentelemetry-client-cohttp-lwt

This is a Lwt-friendly collector that uses cohttp to send
signals to some other collector (e.g. `otelcol`). It must be run
inside a `Lwt_main.run` scope.

## Opentelemetry-trace

The optional library `opentelemetry.trace`, present if [trace](https://github.com/ocaml-tracing/ocaml-trace) is
installed, provides a collector for `trace`. This collector forwards and translates
events from `trace` into `opentelemetry`. It's only useful if there also is also a OTEL collector.

## License

MIT

## Semantic Conventions

Not supported yet.

- [ ] [metrics](https://opentelemetry.io/docs/reference/specification/metrics/semantic_conventions/)
- [ ] [traces](https://opentelemetry.io/docs/reference/specification/trace/semantic_conventions/)
- [ ] [resources](https://opentelemetry.io/docs/reference/specification/resource/semantic_conventions/)
