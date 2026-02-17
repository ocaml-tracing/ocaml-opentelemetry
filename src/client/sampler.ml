type t = {
  proba_accept: float;
  rng: Random.State.t;
  n_seen: int Atomic.t;
  n_accepted: int Atomic.t;
}

let create ~proba_accept () : t =
  if proba_accept < 0. || proba_accept > 1. then
    invalid_arg "sampler: proba_accept must be in [0., 1.]";
  {
    proba_accept;
    rng = Random.State.make_self_init ();
    n_seen = Atomic.make 0;
    n_accepted = Atomic.make 0;
  }

let[@inline] proba_accept self = self.proba_accept

let actual_rate (self : t) : float =
  let accept = Atomic.get self.n_accepted in
  let total = Atomic.get self.n_seen in

  if total = 0 then
    1.
  else
    float accept /. float total

let accept (self : t) : bool =
  Atomic.incr self.n_seen;

  (* WARNING: Random.State.float is not safe to call concurrently on the
     same state from multiple domains. If a sampler is shared across domains,
     consider creating one sampler per domain. *)
  let n = Random.State.float self.rng 1. in
  let res = n < self.proba_accept in

  if res then Atomic.incr self.n_accepted;
  res
