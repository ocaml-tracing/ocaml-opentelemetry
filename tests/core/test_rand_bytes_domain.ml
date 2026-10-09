module R = Opentelemetry_core.Rand_bytes

let () =
  let domains =
    Array.init 8 (fun _ ->
        Domain.spawn (fun () ->
            Array.init 1_000 (fun _ ->
                R.default_rand_bytes_16 (), R.default_rand_bytes_8 ())))
  in
  let traces = Hashtbl.create 8_000 and spans = Hashtbl.create 8_000 in
  Array.iter
    (fun domain ->
      Array.iter
        (fun (trace, span) ->
          assert (Bytes.length trace = 16);
          assert (Bytes.length span = 8);
          assert (not (Hashtbl.mem traces trace));
          assert (not (Hashtbl.mem spans span));
          Hashtbl.add traces trace ();
          Hashtbl.add spans span ())
        (Domain.join domain))
    domains
