
# Trace

[![Build and Test](https://github.com/ocaml-tracing/ocaml-trace/actions/workflows/main.yml/badge.svg)](https://github.com/ocaml-tracing/ocaml-trace/actions/workflows/main.yml)

This small library provides basic types that can be used to instrument
a library or application, either by hand or via a ppx.

## Features

- [x] spans
- [x] messages
- [x] counters
- [ ] other metrics?
- [x] ppx to help instrumentation

## Usage

To instrument your code, you can simply add `trace` to your dune/opam files, and then
write code like such:

```ocaml
let f x =
  Trace.with_span ~__FILE__ ~__LINE__ "inside-f" @@ fun _sp ->
  (* … code for f *)

let g x =
  Trace.with_span ~__FILE__ ~__LINE__ "inside-g" @@ fun _sp ->
  let y = f x in
  (* … code for f *)

let () =
  Some_trace_backend.setup () @@ fun () ->
  let result = g 42 in
  print_result result
```

The file `test/t1.ml` follows this pattern, using `trace-tef` as a simple backend
that emits one JSON object per span/message:

```ocaml
let run () =
  Trace.set_process_name "main";
  Trace.set_thread_name "t1";

  let n = ref 0 in

  for _i = 1 to 50 do
    Trace.with_span ~__FILE__ ~__LINE__ "outer.loop" @@ fun _sp ->
    for _j = 2 to 5 do
      incr n;
      Trace.with_span ~__FILE__ ~__LINE__ "inner.loop" @@ fun _sp ->
      Trace.messagef (fun k -> k "hello %d %d" _i _j);
      Trace.message "world";
      Trace.counter_int "n" !n
    done
  done

let () =
  Trace_tef.with_setup ~out:(`File "trace.json") () @@ fun () ->
  run ()
```

After running this, the file "trace.json" will contain something like:
```json
[{"pid":2,"name":"process_name","ph":"M","args": {"name":"main"}},
{"pid":2,"tid": 3,"name":"thread_name","ph":"M","args": {"name":"t1"}},
{"pid":2,"cat":"","tid": 3,"ts": 2.00,"name":"hello 1 2","ph":"I"},
{"pid":2,"cat":"","tid": 3,"ts": 3.00,"name":"world","ph":"I"},
{"pid":2,"tid":3,"ts":4.00,"name":"c","ph":"C","args": {"n":1}},
…
```

Opening it in https://ui.perfetto.dev we get something like this:

![screenshot of perfetto UI](media/ui.png)

## ppx_trace

On OCaml >= 4.12, and with `ppxlib` installed, you can install `ppx_trace`.
This is a preprocessor that will rewrite like so:

```ocaml
let%trace f x y z =
  do_sth x;
  do_sth y;
  begin
    let%trace () = "sub-span" in
    do_sth z
  end
```

This more or less corresponds to:

```ocaml
let f x y z =
  let _trace_span = Trace_core.enter_span ~__FILE__ ~__LINE__ "Foo.f" in
  match
    do_sth x;
    do_sth y;
    begin
      let _trace_span = Trace_core.enter_span ~__FILE__ ~__LINE__ "sub-span" in
      match do_sth z with
      | res ->
        Trace_core.exit_span _trace_span;
        res
      | exception e ->
        Trace_core.exit_span _trace_span
        raise e
    end;
  with
  | res ->
    Trace_core.exit_span _trace_span
    res
  | exception e ->
    Trace_core.exit_span _trace_span
    raise e
```

Alternatively, a name can be provided for the span, which is useful if you want
to access it and use functions like `Trace.add_data_to_span`:


```ocaml
let%trace f x y z =
  do_sth x;
  do_sth y;
  begin
    let%trace _sp = "sub-span" in
    do_sth z;
    Trace.add_data_to_span _sp ["x", `Int 42]
  end
```

### Dune configuration

In your `library` or `executable` stanza, add: `(preprocess (pps ppx_trace))`.
The dependency on `trace.core` is automatically added. You still need to
configure a backend to actually do collection.

## Backends (collector implementations)

Concrete tracing or observability formats such as:

- [x] Fuchsia (see [the spec](https://fuchsia.dev/fuchsia-src/reference/tracing/trace-format) and [tracing](https://github.com/janestreet/tracing).
        Can be opened in https://ui.perfetto.dev)
- Catapult
  * [x] light bindings here with `trace-tef`.
        (Can be opened in https://ui.perfetto.dev)
  * [x] backend for [tldrs](https://github.com/imandra-ai/tldrs), a
        small rust daemon that aggregates TEF traces from multiple processes/clients
        into a single `.jsonl` file
  * [x] [tldrs](https://github.com/imandra-ai/tldrs), to collect TEF traces from multiple processes in a clean way.
        This requires the rust `tldrs` program to be in path.
  * ~~[ ] richer bindings with [ocaml-catapult](https://github.com/imandra-ai/catapult),
        with multi-process backends, etc.~~ (subsumed by tldrs)
- [x] Tracy (see [ocaml-tracy](https://github.com/ocaml-tracing/ocaml-tracy), more specifically `tracy-client.trace`)
- [x] Opentelemetry (see [ocaml-opentelemetry](https://github.com/ocaml-tracing/ocaml-opentelemetry/), in `opentelemetry.trace`)
- [ ] landmarks?
- [ ] native perfetto backend
- [ ] OCaml runtime events
- [ ] Logs (only for messages, obviously)

Collectors are now more composable and replace `trace.subscribers`.

## Subscribers

Not a thing anymore.
