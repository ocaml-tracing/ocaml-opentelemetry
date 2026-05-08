open struct
  type cell = {
    mu: Mutex.t;
    mutable rand: Random.State.t option;
  }

  let cells = Array.init 8 (fun _ -> { mu = Mutex.create (); rand = None })

  let ( let@ ) = ( @@ )

  let with_shard_rand i (f : Random.State.t -> 'a) : 'a =
    let cell = Array.get cells (i land 0b111) in
    let@ () = Util_mutex.protect cell.mu in
    let rand =
      match cell.rand with
      | Some r -> r
      | None ->
        let r = Random.State.make_self_init () in
        cell.rand <- Some r;
        r
    in
    f rand
end

(** What rand state do we use? *)
let[@inline] shard () : int = Thread.id (Thread.self ())

let default_rand_bytes_8 () : bytes =
  let shard = shard () in
  let@ rand = with_shard_rand shard in

  let b = Bytes.create 8 in
  for i = 0 to 1 do
    (* rely on the stdlib's [Random] being thread-or-domain safe *)
    let r = Random.State.bits rand in
    (* 30 bits, of which we use 24 *)
    Bytes.set b (i * 3) (Char.chr (r land 0xff));
    Bytes.set b ((i * 3) + 1) (Char.chr ((r lsr 8) land 0xff));
    Bytes.set b ((i * 3) + 2) (Char.chr ((r lsr 16) land 0xff))
  done;
  let r = Random.State.bits rand in
  Bytes.set b 6 (Char.chr (r land 0xff));
  Bytes.set b 7 (Char.chr ((r lsr 8) land 0xff));
  b

let default_rand_bytes_16 () : bytes =
  let shard = shard () in
  let@ rand = with_shard_rand shard in

  let b = Bytes.create 16 in
  for i = 0 to 4 do
    let r = Random.State.bits rand in
    (* 30 bits, of which we use 24 *)
    Bytes.set b (i * 3) (Char.chr (r land 0xff));
    Bytes.set b ((i * 3) + 1) (Char.chr ((r lsr 8) land 0xff));
    Bytes.set b ((i * 3) + 2) (Char.chr ((r lsr 16) land 0xff))
  done;
  let r = Random.State.bits rand in
  Bytes.set b 15 (Char.chr (r land 0xff));
  (* last byte *)
  b

let rand_bytes_16_ref = ref default_rand_bytes_16

let rand_bytes_8_ref = ref default_rand_bytes_8

(** Generate a 16B identifier *)
let[@inline] rand_bytes_16 () = !rand_bytes_16_ref ()

(** Generate an 8B identifier *)
let[@inline] rand_bytes_8 () = !rand_bytes_8_ref ()
