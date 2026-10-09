open struct
  type state = {
    mutable pid: int;
    mutable rand: Random.State.t;
    checks: int Atomic.t;
  }

  let key =
    Opentelemetry_domain.DLS.new_key (fun () ->
        {
          pid = Unix.getpid ();
          rand = Random.State.make_self_init ();
          checks = Atomic.make 3;
        })

  let get_rand () =
    let self = Opentelemetry_domain.DLS.get key in
    if
      Opentelemetry_domain.is_main_domain ()
      && Atomic.fetch_and_add self.checks (-1) <= 1
    then (
      (* need to check if we're in a fork. reseed to decorrelate spans/traces
         between parent and child *)
      Atomic.set self.checks 10_000;
      let pid = Unix.getpid () in
      if pid <> self.pid then (
        self.rand <- Random.State.make_self_init ();
        self.pid <- pid
      )
    );
    self.rand
end

let default_rand_bytes_8 () : bytes =
  let rand = get_rand () in
  let b = Bytes.create 8 in
  Bytes.set_int64_le b 0 (Random.State.bits64 rand);
  b

let default_rand_bytes_16 () : bytes =
  let rand = get_rand () in
  let b = Bytes.create 16 in
  Bytes.set_int64_le b 0 (Random.State.bits64 rand);
  Bytes.set_int64_le b 8 (Random.State.bits64 rand);
  b

let rand_bytes_16_ref = ref default_rand_bytes_16

let rand_bytes_8_ref = ref default_rand_bytes_8

(** Generate a 16B identifier *)
let[@inline] rand_bytes_16 () = !rand_bytes_16_ref ()

(** Generate an 8B identifier *)
let[@inline] rand_bytes_8 () = !rand_bytes_8_ref ()
