open Hegel
module T = Opentelemetry.Trace_context.Tracestate

let max_th = (1 lsl 56) - 1

let member =
  Generators.from_regex "[a-z][a-z0-9_*/-]{0,8}=[!-+--<>-~]{1,10}"
    ~fullmatch:true ()

let sep = Generators.sampled_from [ ","; " ,"; ", "; " , "; ",\t" ]

let ws = Generators.sampled_from [ ""; " "; "\t" ]

let () =
  run_hegel_test (fun tc ->
      let s = draw ~label:"s" tc (Generators.text ()) in
      ignore (T.get_ot_th s : int64 option))

let () =
  run_hegel_test (fun tc ->
      let hex =
        draw ~label:"hex" tc
          (Generators.from_regex "[0-9a-f]{1,14}" ~fullmatch:true ())
      in
      let rv =
        draw_silent tc
          (Generators.sampled_from [ ""; "rv:0123456789abcd;"; "foo:bar;" ])
      in
      let others =
        draw ~label:"others" tc (Generators.lists member ~max_size:5 ())
      in
      assume tc
        (not (List.exists (fun m -> String.starts_with ~prefix:"ot=" m) others));
      let pos =
        draw ~label:"pos" tc (Generators.integers ~min_value:0 ~max_value:5 ())
      in
      let pos = min pos (List.length others) in
      let ot = "ot=" ^ rv ^ "th:" ^ hex in
      let members =
        List.filteri (fun i _ -> i < pos) others
        @ (ot :: List.filteri (fun i _ -> i >= pos) others)
      in
      let s =
        List.fold_left
          (fun acc m ->
            let sep = draw_silent tc sep in
            if acc = "" then
              m
            else
              acc ^ sep ^ m)
          "" members
      in
      let s = draw_silent tc ws ^ s ^ draw_silent tc ws in
      let n = String.length hex in
      let expected =
        Int64.shift_left (Int64.of_string ("0x" ^ hex)) (4 * (14 - n))
      in
      assert (T.get_ot_th s = Some expected))

let () =
  run_hegel_test (fun tc ->
      let s = draw ~label:"s" tc (Generators.text ()) in
      let th =
        Int64.of_int
          (draw ~label:"th" tc
             (Generators.integers ~min_value:0 ~max_value:max_th ()))
      in
      assert (T.get_ot_th (T.set_ot_th s th) = Some th))
