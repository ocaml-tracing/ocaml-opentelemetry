# 0.12

- use `current_span` when entering spans or sending messages
- add `Trace.Ambient_span_provider.t` concept, to track the current span.
    It is not part of the collector and is optional.
- add `trace.thread-local-storage` optional library that implements the `Ambient_span_provider.t`
- add a runtime events collector, + test, in `trace-runtime-events`
- add `{thread,process}_sort_index` extension + TEF support

# 0.11

- entire rework of the collector, now lighter, and using an open sum type
    for `span`. No global state is required anymore.
- add `enabled` to the collector
- extensible `metric`; pass level around in collector
- remove unused deps on hmap, thread-local-storage
- add `Trace.with_setup_collector`
- add `trace.debug` to find what spans were not closed on exit
- remove dead code and `on_tracing_error`
- remove subscriber entirely
- core: remove `current_span` from collector
- update deps to ppxlib=0.37~
- breaking: use poly variants for `user_data/span_flavor`
- use `at_exit` in `trace_tef` and `tldrs`
- fix fuchsia: bound check

# 0.10

- breaking: manual spans now take a `explicit_span_ctx` as parent, that
    can potentially be transmitted across processes/machines. It also
    is intended to be more compatible with OTEL.
- breaking `trace.subscriber`: timestamps are `int64`ns now, not floats
- breaking `trace`: pass a `string` trace_id in manual spans, which helps
    for backends such as opentelemetry. It's also useful for extensions.

- refactor `trace-fuchsia`: full revamp of the library, modularized, using subscriber API
- refactor `trace-tef`: split into exporter,writer,subscriber, using subscriber API
- feat: add `trace.event`, useful for background threads
- feat `trace.subscriber`: add `Span_tbl`, and a depopt on picos_aux
- feat `trace.subscriber`: tee a whole array at once
- feat tef-tldrs: use EMIT_TEF_AT_EXIT
- feat `trace.subscriber`: depopt on unix for timestamps
- refactor `trace-tef`: depopt on unix for TEF timestamps

# 0.9.1


- fix: upper bound on ppxlib
- feat trace-tef: print names of non-closed spans upon exit
- fix: block signals in background threads

# 0.9

- add an extensible sum type, so users can implement custom events. For example
    an OTEL collector can provide custom events to link two spans to one another.

# 0.8

- add `trace.subscriber` instead of a separate library
- add `trace-tef.tldrs`, to trace multiple processes easily (with external rust daemon)

- breaking: `trace-tef`: use `mtime.now`, not a counter, for multiproc
- `trace-fuchsia`: require thread-local-storage 0.2

# 0.7

- feat: add levels to `Trace_core`. Levels are similar to `logs` levels, to help control verbosity.
- add hmap as a depopt (#28)

- fix: truncate large strings in fuchsia

# 0.6

- add `ppx_trace` for easier instrumentation.
  * `let%trace span = "foo" in …` will enter a scope `span` named "foo"
  * `let%trace () = "foo" in …` will enter a scope named "foo" with a hidden name
- add `trace-fuchsia` backend, which produces traces in the binary format
    of [fuchsia](https://fuchsia.dev/fuchsia-src/reference/tracing/trace-format).
    These traces are reasonably efficient to produce (~60ns per span on my machines)
    and reasonably compact on disk, at least compared to the TEF backend.

# 0.5

- perf: reduce overhead in trace-tef
- perf: add Mpsc_queue, adapted from picos, to trace-tef

# 0.4

- add `?data` to `counter_int` and `counter_float`
- add `float` to user data
- add `add_data_to_current_span` and `add_data_to_manual_span`
- make `explicit_span.meta` mutable
- trace-tef: write to `trace.json` if env variable `TRACE` is either 1 or true
- trace-tef: emit function name, if provided, as a metadata key/value pair
- re-export trace.core in trace

- perf: in trace-tef, use broadcast instead of signal in the job queue

# 0.3

- add explicit spans, for more precise tracing
- rename repo to ocaml-trace
- trace-tef: add a ticker thread to ensure we flush the file regularly

# 0.2

- trace-tef: additional argument to `with_setup`; env for "stdout"/"stderr"
- refactor: avoid conflicting with stdlib `Trace` module by adding sublibrary `trace.core`.
    Programs that use `compiler-libs.toplevel` should use `trace.core`
    directly, because using `trace` will cause linking errors.
- perf(trace-tef): improve behavior of collector under contention by
    pulling all events at once in the worker

# 0.1

initial release
