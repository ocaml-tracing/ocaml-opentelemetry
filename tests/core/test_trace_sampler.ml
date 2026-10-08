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
