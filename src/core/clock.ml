open Opentelemetry_atomic

type t = { now: unit -> Timestamp_ns.t } [@@unboxed]
(** A clock: can get the current timestamp, with nanoseconds precision *)

let[@inline] now (self : t) : Timestamp_ns.t = self.now ()

open struct
  module TS = Timestamp_ns

  let ns_in_a_day = Int64.(mul 1_000_000_000L (of_int (24 * 3600)))

  (** Current unix timestamp in nanoseconds *)
  let[@inline] now_ptime_ () : TS.t =
    let d, ps = Ptime_clock.now_d_ps () in
    let d = Int64.(mul (of_int d) ns_in_a_day) in
    let ns = Int64.(div ps 1_000L) in
    Int64.(add d ns)
end

(** Clock that uses ptime. *)
let ptime_clock : t = { now = now_ptime_ }

(** Same as [now ptime_clock] *)
let now_ptime = now_ptime_

(** Singleton clock *)
module Main = struct
  open struct
    let main : t Atomic.t = Atomic.make ptime_clock
  end

  let[@inline] get () = Atomic.get main

  (** Set the current clock *)
  let set t : unit = Util_atomic.update_cas main (fun _ -> (), t)
end

(** Timestamp using the main clock *)
let[@inline] now_main () = now (Main.get ())
