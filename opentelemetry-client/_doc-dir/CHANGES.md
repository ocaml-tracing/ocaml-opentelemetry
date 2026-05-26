## 0.91.1

- fix: lazy init of random generators
- fix: in trace, respect ~parent:P_none

## 0.91

- expose Self_debug.level_above
- config: better defaults in Sdk, have batching enabled by default

- better error message for otlp http failures
- bounded queue: provide a per-item measure function for better errors/metrics
- fix: retries are self_debug logged at warning level
- move from ocurl to curl as a dep

## 0.90

- major refactor: split library into `opentelemetry.core`, `opentelemetry`,
  `opentelemetry.util`, `opentelemetry.emitter`, `opentelemetry.atomic`, revamp internals
- per-signal providers: separate trace, meter, and logger providers replace
  the single monolithic exporter
- `opentelemetry.ambient-context` is now a standalone library, once again
- new `opentelemetry-client-ocurl-lwt` package
- client: split `opentelemetry-client-sync` off of the main client library
- client: add support for `http/json` protocol alongside `http/protobuf`
- client: add HTTP retry with exponential backoff
- client: overhaul bounded queue; introduce generic consumer framework
- client: add `Exporter_add_batching`, `Emitter_add_batching`, `Emitter_sample`,
  `Emitter_limit_interval` combinators. Batching is factored out of individual
  client libraries.
- client: add sampler as an emitter transformer
- client: add `exporter_stdout` and `debug_exporter`
- client: add `self_metrics` and `self_debug` to exporters
- client: add `after_shutdown` callback in ocurl/ocurl-lwt clients
- `Span.dummy`: inert span that is never modified
- `Span.record_exception` now also sets the span status to error
- `Span.set_span_status` added in `opentelemetry.trace`
- `Span`: carry flags to `span_link`
- `Span`: now mutable thanks to ocaml-protoc 4.0, replaces old `Scope.t` entirely
- `Meter.emit` and `Meter_provider.emit_l` added
- emitter: add `flat_map`, `tap`, `to_list`, `enabled` combinators
- clock abstraction added; `ptime` used by default in logger and metrics
- interval limiter used for `metrics_callbacks`
- update to OTEL spec 1.8.0
- update semantic conventions
- various bug fixes and performance improvements

## 0.12

- breaking: change `Collector.cleanup` so it takes a callback

- feat: add Eio collector
- feat: add Logs integration
- Specify and document the Signal_gatherer API
- feat: add `Globals.service_version`
- add `pp` implemtation for `Client_ocurl.Config`
- feat: adapt to trace 0.10

- fix concurrency issues, make the libraries thread safe
- add many tests
- fix: opentelemetry exception attr spec
- Add tests for Opentelemetry.Client.Config

- large refactorings to factor out batching logic out of cohttp-lwt client,
    also encoding logic. The code for collectors is now much cleaner.

## 0.11.2

- fix: opentelemetry-client-ocurl: don't block signals on Windows
- fix otel-client-ocurl: use ptime timestamps for self metrics

## 0.11.1

- add missing sample argument to `Traceparent.to_value`

## 0.11

- add `Span_kind.t`, add {kind,set_kind} to `Scope`
- expose `Span_status` types
- add `Scope.set_span_status`
- add `record_exception`
- otel.trace: extension points for links, record_exn, kind
- otel.trace: set status of a span based on `exception.message`

- add cohttp upper bound version constraint
- in backends, call `tick()` before cleaning up
- reduce memory usage of `Scope.t` (@tatchi)

- remove dependency on ambient-context, vendor/inline/specialize it

## 0.10

- feat: add support for per-signal urls (by @tatchi)
- build: disable protobuf regeneration during normal library use
- fix: emit GC metrics even in the absence of custom metrics

## 0.9

- compat with trace 0.7

## 0.8

- feat: add dep on `hmap`, add standard keys to carry around a span context or trace id
- add semantic conventions for code and HTTP

- better debug message in curl backend
- make otel-trace a bit more lightweight

## 0.7

- add Span_link.of_span_ctx, Scope.to_span_ctx, dummy values
- feat: add Span_context, as required by OTEL API guidelines
- feat: record backtraces in error spans
- compat with trace 0.6
- ocurl: add ticker_interval_ms config
- ocurl: do some self-tracing optionally
- move protobuf code to opentelemetry.proto

- perf: rewrite parsing+printing for span ctx as w3c trace ctx
- perf: when we get multiple messages, check batches only once
- perf: use ocaml-protoc 3.0.1 for codegen, with faster pbrt

## 0.6

- fix ticker thread shutdown
- migrated to OTEL proto files v1.0
- replace `Thread_local` with `ocaml-ambient-context`, allowing for implicit scope in Lwt/Eio contexts (#34)
- update `ocaml-trace` interface to use the new `trace.0.3`-style API (breaking, see #34)

## 0.5

- new implementation for ocurl backend, using ezcurl and queues
- refactor lwt: Use `try%lwt` over `Lwt.catch`
- add `opentelemetry.trace` (optional, depends on `ocaml-trace`)

## 0.4

- expose `Scope.get_surrounding`
- rehault of GC metrics
- `Trace.with_` now has `force_new_trace_id` param
- use thread-local storage to store global scope
- add `Span_link` module
- add a `Globals.default_span_kind` ref to specify default span kind

- fix(otel-lwt): missing modules now re-exported
- fix(client-ocurl): fix `tick` version used in the absence of bg thread

- drop dep on ocaml-protoc as the generated code is checked-in
- update vendored otel to 0.19

## 0.3

- improve error reporting from ocurl exporter
- improve GC sample collection
- feat(ocurl): simpler, cleaner backend implementation, with graceful exit
- config: make `Config.t` private (breaking)

## 0.2

- require pbrt only, use ocaml-protoc as a lint
- add `Metrics_callbacks` module
- add histogram metrics (untested)
- basic support for logs
- expose `tick` function (useful in the absence of a background thread)
- debug the library is set via `OTEL_OCAML_DEBUG`
- provide conventions for standard metrics
- add runtime attrs to GC stats
