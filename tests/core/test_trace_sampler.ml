open Opentelemetry
module S = Trace_sampler

let () =
  List.iter
    (fun p ->
      let th = S.Private_.threshold_of_ratio p in
      Printf.printf "threshold_of_ratio %g = 0x%014Lx (%S)\n" p th
        (if p > 0. then
           Trace_context.Tracestate.set_ot_th "" th
         else
           "-"))
    [ 0.; 1e-3; 0.01; 0.5; 1. ]

let tid_lo = Trace_id.of_hex "4bf92f3577b34da6a300000000000001"

let tid_hi = Trace_id.of_hex "4bf92f3577b34da6a3ce929d0e0e4736"

let () =
  print_endline "";
  List.iter
    (fun hex ->
      Printf.printf "randomness %s = 0x%014Lx\n" hex
        (S.Private_.randomness (Trace_id.of_hex hex)))
    [
      "4bf92f3577b34da6a3ce929d0e0e4736";
      "00000000000000000000000000000001";
      "ffffffffffffffffffffffffffffffff";
    ]

let samplers =
  S.
    [
      always_on;
      always_off;
      trace_id_ratio 0.5;
      parent_based always_on;
      parent_based (trace_id_ratio 0.5);
    ]

let parents =
  S.
    [
      "none", No_parent, "";
      "none+ts", No_parent, "v=1";
      "sampled", Parent_sampled, "v=1";
      "not_sampled", Parent_not_sampled, "v=1";
      "not_sampled+th", Parent_not_sampled, "ot=th:8,v=1";
    ]

let () =
  print_endline "";
  List.iter
    (fun s ->
      List.iter
        (fun (pname, parent, trace_state) ->
          List.iter
            (fun (tname, tid) ->
              let sampled, ts = S.decide s ~parent ~trace_state tid in
              Format.printf "decide %a %s %s = %B %S@." S.pp s pname tname
                sampled ts)
            [ "lo", tid_lo; "hi", tid_hi ])
        parents)
    samplers

let () =
  let sampler = S.parent_based S.always_off in
  assert (not (fst (S.decide sampler ~parent:No_parent ~trace_state:"" tid_hi)));
  assert (fst (S.decide sampler ~parent:Parent_sampled ~trace_state:"" tid_hi));
  assert (
    not
      (fst (S.decide sampler ~parent:Parent_not_sampled ~trace_state:"" tid_hi)))

let () =
  print_endline "";
  Format.printf "of_env (unset) = %a@." S.pp (S.of_env ());
  List.iter
    (fun (sampler, arg) ->
      Unix.putenv "OTEL_TRACES_SAMPLER" sampler;
      Unix.putenv "OTEL_TRACES_SAMPLER_ARG" arg;
      Format.printf "of_env %S %S = %a@." sampler arg S.pp (S.of_env ()))
    [
      "always_on", "";
      "always_off", "";
      "traceidratio", "0.25";
      "traceidratio", "nope";
      "traceidratio", "2";
      "parentbased_always_on", "";
      "parentbased_always_off", "";
      "parentbased_traceidratio", "0.001";
      "bogus", "";
    ]

(* random-trace-id flag: set on fresh trace IDs, propagated from parents *)
let () =
  S.set None;
  let flags (sp : Span.t) = Span.trace_flags sp in
  let random sp = Trace_flags.is_random (flags sp) in
  Tracer.with_ "root" (fun root ->
      assert (random root);
      assert (Trace_flags.is_sampled (flags root));
      Tracer.with_ "child" (fun child -> assert (random child));
      Tracer.with_ ~force_new_trace_id:true "restart" (fun sp ->
          assert (random sp)));
  let ctx_of flags =
    Span_ctx.make ~trace_flags:(Trace_flags.of_int flags) ~trace_id:tid_hi
      ~parent_id:(Span_id.create ()) ()
  in
  List.iter
    (fun f ->
      let parent_ctx = ctx_of f in
      Tracer.with_ ~parent_ctx "remote child" (fun sp ->
          Printf.printf "parent flags %02x -> child flags %02x\n" f
            (Trace_flags.to_int (flags sp));
          assert (
            random sp = Trace_flags.is_random (Span_ctx.trace_flags parent_ctx));
          assert (
            Bytes.to_string
              (Span_ctx.to_w3c_trace_context (Span.to_span_ctx sp))
            |> fun s ->
            String.sub s 53 2
            = Printf.sprintf "%02x" (Trace_flags.to_int (flags sp)))))
    [ 0x00; 0x01; 0x02; 0x03 ];
  (* explicit trace ID: we don't know if it's random *)
  Tracer.with_ ~trace_id:tid_lo "explicit" (fun sp -> assert (not (random sp)))
