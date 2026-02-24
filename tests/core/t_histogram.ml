open Opentelemetry

(** A deterministic clock that always returns timestamp 0 *)
let dummy_clock : Clock.t = { Clock.now = (fun () -> 0L) }

let emit h = h.Instrument.emit ~clock:dummy_clock ()

let pp_metrics metrics = List.iter (Format.printf "%a@." Metrics.pp) metrics

(* ------------------------------------------------------------------ *)
(* Test 1: one value per bucket, plus one in the overflow bucket *)
(* bounds [1; 2; 5] → 4 buckets: (≤1) (1,2] (2,5] (5,∞) *)
let () =
  let h =
    Instrument.Histogram.create ~name:"test.latency"
      ~description:"test histogram" ~bounds:[ 1.; 2.; 5. ] ()
  in
  Instrument.Histogram.record h 0.5;
  (* bucket 0: ≤1   *)
  Instrument.Histogram.record h 1.5;
  (* bucket 1: ≤2   *)
  Instrument.Histogram.record h 3.0;
  (* bucket 2: ≤5   *)
  Instrument.Histogram.record h 10.;
  (* bucket 3: >5   *)
  (* count=4  sum=15.0  bucket_counts=[1;1;1;1] *)
  pp_metrics (emit h)

(* ------------------------------------------------------------------ *)
(* Test 2: multiple values pile into the same bucket *)
let () =
  let h = Instrument.Histogram.create ~name:"test.size" ~bounds:[ 1.; 5. ] () in
  Instrument.Histogram.record h 0.1;
  Instrument.Histogram.record h 0.2;
  Instrument.Histogram.record h 0.3;
  (* 3 values in bucket 0 *)
  Instrument.Histogram.record h 2.0;
  (* 1 value  in bucket 1 *)
  (* count=4  sum=2.6  bucket_counts=[3;1;0] *)
  pp_metrics (emit h)

(* ------------------------------------------------------------------ *)
(* Test 3: empty histogram *)
let () =
  let h =
    Instrument.Histogram.create ~name:"test.empty" ~bounds:[ 1.; 2.; 5. ] ()
  in
  (* count=0  sum=0.0  bucket_counts=[0;0;0;0] *)
  pp_metrics (emit h)

(* ------------------------------------------------------------------ *)
(* Test 4: value exactly on a bound goes into that bound's bucket *)
let () =
  let h =
    Instrument.Histogram.create ~name:"test.boundary" ~bounds:[ 1.; 2.; 5. ] ()
  in
  Instrument.Histogram.record h 1.0;
  (* exactly on bound → bucket 0 *)
  Instrument.Histogram.record h 2.0;
  (* exactly on bound → bucket 1 *)
  Instrument.Histogram.record h 5.0;
  (* exactly on bound → bucket 2 *)
  (* count=3  sum=8.0  bucket_counts=[1;1;1;0] *)
  pp_metrics (emit h)
