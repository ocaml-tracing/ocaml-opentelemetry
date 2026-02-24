open Opentelemetry_emitter

type t = {
  emit: Metrics.t Emitter.t;
  clock: Clock.t;
}

(** Dummy meter, always disabled *)
let dummy : t = { emit = Emitter.dummy; clock = Clock.ptime_clock }

let[@inline] enabled (self : t) = Emitter.enabled self.emit

let[@inline] emit1 (self : t) (m : Metrics.t) : unit =
  Emitter.emit self.emit [ m ]

let of_exporter (exp : Exporter.t) : t =
  let emit =
    Emitter.make ~signal_name:"metrics"
      ~emit:(fun ms -> exp.Exporter.export (Any_signal_l.Metrics ms))
      ()
  in
  { emit; clock = Clock.Main.get () }

(** Global list of raw metric callbacks, collected alongside {!Instrument.all}.
*)
let cbs_ : (clock:Clock.t -> unit -> Metrics.t list) Alist.t = Alist.make ()

let add_cb (f : clock:Clock.t -> unit -> Metrics.t list) : unit =
  Alist.add cbs_ f

let collect (self : t) : Metrics.t list =
  let clock = self.clock in
  let acc = ref [] in
  Instrument.Internal.iter_all (fun f ->
      acc := List.rev_append (f ~clock ()) !acc);
  List.iter
    (fun f -> acc := List.rev_append (f ~clock ()) !acc)
    (Alist.get cbs_);
  List.rev !acc

module Instrument = Instrument

module type INSTRUMENT_IMPL = Instrument.CUSTOM_IMPL

module Make_instrument = Instrument.Make
module Int_counter = Instrument.Int_counter
module Float_counter = Instrument.Float_counter
module Int_gauge = Instrument.Int_gauge
module Float_gauge = Instrument.Float_gauge
module Histogram = Instrument.Histogram
