# Migration guide: v0.12 → v0.13

This guide covers breaking changes when upgrading from v0.12.

## 1. Backend setup: `Collector` → `Sdk` + `Exporter`

v0.12 used a first-class module `BACKEND` installed into a global slot via
`Collector.set_backend`.  v0.13 replaces this with a plain record `Exporter.t`
installed via `Sdk.set`.

The `with_setup` helper in each client library still exists, so if you use that
you mainly need to rename the module.

```ocaml
(* v0.12 *)
Opentelemetry_client_ocurl.with_setup ~config () (fun () ->
  (* your code *)
  ())

(* v0.13: same call, internals changed; ~stop removed, ~after_shutdown added *)
Opentelemetry_client_ocurl.with_setup
  ~after_shutdown:(fun _exp -> ())
  ~config () (fun () ->
  (* your code *)
  ())
```

If you called `setup`/`remove_backend` manually:

```ocaml
(* v0.12 *)
Opentelemetry_client_ocurl.setup ~config ()
(* ... *)
Opentelemetry_client_ocurl.remove_backend ()

(* v0.13 *)
Opentelemetry_client_ocurl.setup ~config ()
(* ... *)
Opentelemetry_client_ocurl.remove_exporter ()
```

The `~stop:bool Atomic.t` parameter has been removed from the ocurl client.
Use `Sdk.active ()` (an `Aswitch.t`) to detect shutdown instead.

## 2. `Trace.with_` → `Tracer.with_`, callback gets a `Span.t`

The most common migration. The module is renamed and the callback argument type
changes from `Scope.t` to `Span.t`.

```ocaml
(* v0.12 *)
Trace.with_ "my-op" ~attrs:["k", `String "v"] (fun (scope : Scope.t) ->
  Scope.add_event scope (fun () -> Event.make "something happened");
  Scope.add_attrs scope (fun () -> ["extra", `Int 42]);
  do_work ()
)

(* v0.13 *)
Tracer.with_ "my-op" ~attrs:["k", `String "v"] (fun (span : Span.t) ->
  Span.add_event span (Event.make "something happened");
  Span.add_attrs span ["extra", `Int 42];
  do_work ()
)
```

`Trace` is kept as a deprecated alias for `Tracer`.

Key differences on the callback argument:

| v0.12 (`Scope.t`)                          | v0.13 (`Span.t`)                     |
|--------------------------------------------|--------------------------------------|
| `scope.trace_id`                           | `Span.trace_id span`                 |
| `scope.span_id`                            | `Span.id span`                       |
| `Scope.add_event scope (fun () -> ev)`     | `Span.add_event span ev`             |
| `Scope.add_attrs scope (fun () -> attrs)`  | `Span.add_attrs span attrs`          |
| `Scope.set_status scope st`                | `Span.set_status span st`            |
| `Scope.record_exception scope e bt`        | `Span.record_exception span e bt`    |
| `Scope.to_span_ctx scope`                  | `Span.to_span_ctx span`              |
| `Scope.to_span_link scope`                 | `Span.to_span_link span`             |
| `~scope:scope` (pass parent explicitly)    | `~parent:span`                       |

The `~scope` parameter of `Trace.with_` is renamed to `~parent`:

```ocaml
(* v0.12 *)
Trace.with_ "child" ~scope:parent_scope (fun child -> ...)

(* v0.13 *)
Tracer.with_ "child" ~parent:parent_span (fun child -> ...)
```

In addition, `Scope.t` is entirely removed because `Span.t` is now mutable.
For additional efficiency, `Span.t` is directly encodable to protobuf
without the need to allocate further intermediate structures.

## 3. `Logs` → `Logger`, new emit helpers

The `Logs` module is renamed to `Logger` (`Logs` is kept as a deprecated alias).
Direct construction of log records and batch-emit is replaced by convenience
functions.

```ocaml
(* v0.12 *)
Logs.emit [
  Logs.make_str ~severity:Severity_number_warn "something went wrong"
]

Logs.emit [
  Logs.make_strf ~severity:Severity_number_info "processed %d items" n
]

(* v0.13: simple string *)
Logger.log ~severity:Severity_number_warn "something went wrong"

(* v0.13: formatted *)
Logger.logf ~severity:Severity_number_info (fun k -> k "processed %d items" n)
```

If you need to keep the trace/span correlation:

```ocaml
(* v0.12 *)
Logs.emit [
  Logs.make_str ~trace_id ~span_id ~severity:Severity_number_info "ok"
]

(* v0.13 *)
Logger.log ~trace_id ~span_id ~severity:Severity_number_info "ok"
```

`Log_record.make_str` / `Log_record.make` still exist if you need to build
records manually and emit them via a `Logger.t`.

## 4. `Metrics.emit` → emit via a `Meter`

In v0.12 `Metrics.emit` was a top-level function that sent directly to the
collector. In v0.13 metrics go through a `Meter.t`.  For most code the change
is mechanical:

```ocaml
(* v0.12 *)
Metrics.emit [
  Metrics.gauge ~name:"queue.depth" [ Metrics.int ~now depth ]
]

(* v0.13: Meter.default emits to the global provider *)
Meter.emit1 Meter.default
  (Metrics.gauge ~name:"queue.depth" [ Metrics.int ~now depth ])
```

`now` is now obtained from the meter's clock rather than `Timestamp_ns.now_unix_ns ()`:

```ocaml
(* v0.12 *)
let now = Timestamp_ns.now_unix_ns () in
Metrics.emit [ Metrics.sum ~name:"counter" [ Metrics.int ~now n ] ]

(* v0.13 *)
let now = Clock.now Meter.default.clock in
Meter.emit1 Meter.default
  (Metrics.sum ~name:"counter" [ Metrics.int ~now n ])
```

## 5. `Metrics_callbacks.register` → `Meter.add_cb`

```ocaml
(* v0.12 *)
Metrics_callbacks.register (fun () ->
  [ Metrics.gauge ~name:"foo" [ Metrics.int ~now:... 42 ] ])

(* v0.13: callback now receives a clock *)
Meter.add_cb (fun ~clock () ->
  let now = Clock.now clock in
  [ Metrics.gauge ~name:"foo" [ Metrics.int ~now 42 ] ])
```

After registering callbacks you must tell the SDK to drive them:

```ocaml
(* v0.13: call once after setup to schedule periodic emission *)
Meter.add_to_main_exporter Meter.default
```

In v0.12 this was automatic once `Metrics_callbacks.register` was called.

## 6. `GC_metrics.basic_setup` signature unchanged, `setup` changed

`GC_metrics.basic_setup ()` still works. The module has been renamed
to `Gc_metrics`, but the former name persists as a deprecated alias.

If you called the lower-level `GC_metrics.setup exp` directly:

```ocaml
(* v0.12 *)
GC_metrics.setup exporter
(* or *)
GC_metrics.setup_on_main_exporter ()

(* v0.13 *)
Gc_metrics.setup ()              (* uses Meter.default *)
(* or with a specific meter: *)
Gc_metrics.setup ~meter:my_meter ()
```

`GC_metrics.setup_on_main_exporter` has been removed.

## 7. `Collector.on_tick` → `Sdk.add_on_tick_callback`

```ocaml
(* v0.12 *)
Collector.on_tick (fun () -> do_background_work ())

(* v0.13 *)
Sdk.add_on_tick_callback (fun () -> do_background_work ())
```

## 8. `?service_name` parameter removed

`Trace.with_`, `Logs.emit`, and `Metrics.emit` accepted a `?service_name`
override. This is no longer supported per-call; set it once globally:

```ocaml
(* v0.12 *)
Trace.with_ "op" ~service_name:"my-svc" (fun _ -> ...)

(* v0.13: set globally before setup *)
Opentelemetry.Globals.service_name := "my-svc"
Tracer.with_ "op" (fun _ -> ...)
```

## 9. `create_backend` / `BACKEND` module type removed

If you held a reference to a backend module:

```ocaml
(* v0.12 *)
let (module B : Collector.BACKEND) =
  Opentelemetry_client_ocurl.create_backend ~config ()
in
Collector.set_backend (module B)

(* v0.13 *)
let exp : Exporter.t =
  Opentelemetry_client_ocurl.create_exporter ~config ()
in
Sdk.set exp
```

## 10. New features (no migration needed)

- **`Sdk.get_tracer/get_meter/get_logger`**: obtain a provider pre-stamped with
  instrumentation-scope metadata (`~name`, `~version`, `~__MODULE__`).
- **`Trace_provider` / `Meter_provider` / `Log_provider`**: independent
  per-signal providers; useful for testing or multi-backend setups.
- **`Dynamic_enricher`**: register callbacks that inject attributes into every
  span and log record at creation time (wide events).
- **Batch**: much better handling of batching overall.

## Quick checklist

- [ ] `Trace.with_` → `Tracer.with_`; callback argument `Scope.t` → `Span.t`
- [ ] `Scope.add_event`/`add_attrs` → `Span.add_event`/`add_attrs` (no thunk wrapper)
- [ ] `~scope:` → `~parent:` in nested `with_` calls
- [ ] `Logs.emit [Logs.make_str ...]` → `Logger.log`/`Logger.logf`
- [ ] `Metrics.emit [...]` → `Meter.emit1 Meter.default ...`
- [ ] `Metrics_callbacks.register` → `Meter.add_cb` (+ call `Meter.add_to_main_exporter`)
- [ ] `GC_metrics.setup exp` → `Gc_metrics.setup ()`
- [ ] `Collector.on_tick` → `Sdk.add_on_tick_callback`
- [ ] Remove `?service_name` call-site overrides; set `Globals.service_name` once
- [ ] `create_backend` → `create_exporter`; `set_backend` → `Sdk.set`
- [ ] `~stop:bool Atomic.t` removed from ocurl client
