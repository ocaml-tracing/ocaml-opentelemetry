type t = {
  min_interval: Mtime.span Atomic.t;
  last: Mtime.t Atomic.t;
}

let[@inline] min_interval self = Atomic.get self.min_interval

let[@inline] set_min_interval self i = Atomic.set self.min_interval i

let create_atomic ~min_interval () : t =
  { min_interval; last = Atomic.make Mtime.min_stamp }

let create ~min_interval () : t =
  create_atomic ~min_interval:(Atomic.make min_interval) ()

let make_attempt (self : t) : bool =
  let now = Mtime_clock.now () in
  let last = Atomic.get self.last in
  let elapsed = Mtime.span last now in
  if Mtime.Span.compare elapsed (Atomic.get self.min_interval) >= 0 then
    (* attempts succeeds, unless another thread updated [self.last]
       in the mean time, so we return [true] iff the CAS was successful *)
    Atomic.compare_and_set self.last last now
  else
    false
