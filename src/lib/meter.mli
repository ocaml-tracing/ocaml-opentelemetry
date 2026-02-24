(** Builder for instruments and periodic metric emission.

    https://opentelemetry.io/docs/specs/otel/metrics/api/#get-a-meter

    Instruments ({!Int_counter}, {!Histogram}, …) register themselves into a
    global list ({!Instrument.all}) on creation and do not require a meter. A
    {!t} is only needed to wire up periodic collection and emission: call
    {!add_to_exporter} or {!add_to_main_exporter} once after creating your
    instruments. *)

type t = {
  emit: Metrics.t Opentelemetry_emitter.Emitter.t;
  clock: Clock.t;
}

val dummy : t
(** Dummy meter, always disabled *)

val enabled : t -> bool

val of_exporter : Exporter.t -> t
(** Create a meter from an exporter *)

val emit1 : t -> Metrics.t -> unit
(** Emit a single metric directly, bypassing the instrument registry *)

val add_cb : (clock:Clock.t -> unit -> Metrics.t list) -> unit
(** Register a raw global metrics callback. Called alongside all instruments
    when {!collect} runs. Use this for ad-hoc metrics that don't fit the
    structured instrument API. *)

val collect : t -> Metrics.t list
(** Collect metrics from all registered instruments ({!Instrument.all}) and raw
    callbacks ({!add_cb}), using this meter's clock. *)

module Instrument = Instrument
(** Global registry of metric instruments. Re-exported from
    {!Opentelemetry_core.Instrument} for convenience. *)

(** Convenience aliases for the instrument submodules in {!Instrument}. *)

module type INSTRUMENT_IMPL = Instrument.CUSTOM_IMPL

module Make_instrument = Instrument.Make
module Int_counter = Instrument.Int_counter
module Float_counter = Instrument.Float_counter
module Int_gauge = Instrument.Int_gauge
module Float_gauge = Instrument.Float_gauge
module Histogram = Instrument.Histogram
