module R = Opentelemetry_core.Rand_bytes

let draw_last n gen =
  let last = ref (gen ()) in
  for _ = 2 to n do
    last := gen ()
  done;
  !last

let write_all fd b =
  let rec loop off =
    if off < Bytes.length b then (
      let written = Unix.write fd b off (Bytes.length b - off) in
      if written = 0 then
        failwith "pipe write failed"
      else
        loop (off + written)
    )
  in
  loop 0

let read_exact fd n =
  let b = Bytes.create n in
  let rec loop off =
    if off < n then (
      let count = Unix.read fd b off (n - off) in
      if count = 0 then
        failwith "short pipe read"
      else
        loop (off + count)
    )
  in
  loop 0;
  b

let fork_pair n gen width =
  let r, w = Unix.pipe () in
  match Unix.fork () with
  | 0 ->
    Unix.close r;
    write_all w (draw_last n gen);
    Unix.close w;
    Unix._exit 0
  | child ->
    Unix.close w;
    let parent_last = draw_last n gen in
    let child_last = read_exact r width in
    Unix.close r;
    assert (Unix.waitpid [] child = (child, Unix.WEXITED 0));
    assert (parent_last <> child_last)

let () =
  assert (Bytes.length (R.default_rand_bytes_16 ()) = 16);
  fork_pair 2 R.default_rand_bytes_16 16;
  fork_pair 10_000 R.default_rand_bytes_8 8;
  assert (Bytes.length (R.default_rand_bytes_8 ()) = 8)
