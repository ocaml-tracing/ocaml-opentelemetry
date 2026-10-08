open Opentelemetry

let pp_traceparent fmt (trace_id, parent_id) =
  let open Format in
  fprintf fmt "trace_id:%S parent_id:%S" (Trace_id.to_hex trace_id)
    (Span_id.to_hex parent_id)

let pp_span_ctx fmt ctx =
  Format.fprintf fmt "%a sampled:%B remote:%B trace_state:%S" pp_traceparent
    (Span_ctx.trace_id ctx, Span_ctx.parent_id ctx)
    (Span_ctx.sampled ctx) (Span_ctx.is_remote ctx) (Span_ctx.trace_state ctx)

let test_of_value ?trace_state str =
  let open Format in
  printf "@[<v 2>Trace_context.Traceparent.of_value %S:@ %a@]@." str
    (pp_print_result
       ~ok:(fun fmt ctx -> fprintf fmt "Ok %a" pp_span_ctx ctx)
       ~error:(fun fmt msg -> fprintf fmt "Error %S" msg))
    (Trace_context.Traceparent.of_value ?trace_state str)

let () = test_of_value "xx"

let () = test_of_value "00"

let () = test_of_value "00-xxxx"

let () = test_of_value "00-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

let () = test_of_value "00-0123456789abcdef0123456789abcdef"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-xxxx"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-xxxxxxxxxxxxxxxx"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-0123456789abcdef"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-0123456789abcdef-"

let () = test_of_value "00-0123456789abcdef0123456789abcdef-0123456789abcdef-00"

let () = test_of_value "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

let () = test_of_value "03-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

let () = test_of_value "00-ohnonohex7b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

let () = test_of_value "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aazzzzzzb7-01"

let () =
  List.iter
    (fun flags ->
      test_of_value ~trace_state:"ot=th:8,vendor1=t61rcWkgMzE"
        ("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-" ^ flags))
    [ "00"; "01"; "03" ]

let () = print_endline ""

let () =
  let module T = Trace_context.Tracestate in
  let pp_th fmt = function
    | None -> Format.fprintf fmt "None"
    | Some th -> Format.fprintf fmt "Some 0x%014Lx" th
  in
  List.iter
    (fun ts -> Format.printf "get_ot_th %S = %a@." ts pp_th (T.get_ot_th ts))
    [
      "";
      "vendor1=t61rcWkgMzE";
      "ot=th:8";
      "vendor1=t61rcWkgMzE, ot=rv:1234;th:fd7";
      "ot=th:0";
      "ot=th:123456789abcdef";
      "ot=th:xyz";
    ];
  List.iter
    (fun (ts, th) ->
      let ts' = T.set_ot_th ts th in
      Format.printf "set_ot_th %S 0x%014Lx = %S -> %a@." ts th ts' pp_th
        (T.get_ot_th ts'))
    [
      "", 0L;
      "", 0x80000000000000L;
      "vendor1=t61rcWkgMzE,vendor2=00f067aa0ba902b7", 0xfd70a3d70a3d71L;
      "vendor1=t61rcWkgMzE, ot=rv:1234;th:8 ,vendor2=1", 0x40000000000000L;
    ]

let () =
  let ctx =
    Span_ctx.make ~sampled:true ~trace_state:"ot=th:8"
      ~trace_id:(Trace_id.of_hex "4bf92f3577b34da6a3ce929d0e0e4736")
      ~parent_id:(Span_id.of_hex "00f067aa0ba902b7")
      ()
  in
  List.iter
    (fun (k, v) -> Format.printf "header %s: %s@." k v)
    (Trace_context.headers_of_span_ctx ctx)

let () =
  let module T = Trace_context.Tracestate in
  let others = List.init 32 (fun i -> Printf.sprintf "vendor%d=value" i) in
  let update s = String.split_on_char ',' (T.set_ot_th s 0L) in
  let result = update (String.concat "," others) in
  assert (result = "ot=th:0" :: List.filteri (fun i _ -> i < 31) others);
  let result = update (String.concat "," (others @ [ "ot=rv:1" ])) in
  assert (result = "ot=th:0;rv:1" :: List.filteri (fun i _ -> i < 31) others)

let () = print_endline ""

let test_to_value trace_id parent_id =
  let open Format in
  printf "@[<v 2>Trace_context.Traceparent.to_value %a:@ %S@]@." pp_traceparent
    (trace_id, parent_id)
    (Trace_context.Traceparent.to_value ~trace_id ~parent_id ())

let () =
  test_to_value
    (Trace_id.of_hex "4bf92f3577b34da6a3ce929d0e0e4736")
    (Span_id.of_hex "00f067aa0ba902b7")
