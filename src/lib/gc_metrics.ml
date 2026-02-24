open struct
  let bytes_per_word = Sys.word_size / 8

  let[@inline] word_to_bytes n = n * bytes_per_word

  let[@inline] word_to_bytes_f n = n *. float bytes_per_word

  let default_interval_s = 20
end

let get_metrics () : Metrics.t list =
  let gc = Gc.quick_stat () in
  let now = Clock.now_main () in
  let open Metrics in
  let open Conventions.Metrics in
  [
    gauge ~name:Process.Runtime.Ocaml.GC.major_heap ~unit_:"B"
      [ int ~now (word_to_bytes gc.Gc.heap_words) ];
    sum ~name:Process.Runtime.Ocaml.GC.minor_allocated
      ~aggregation_temporality:Metrics.Aggregation_temporality_cumulative
      ~is_monotonic:true ~unit_:"B"
      [ float ~now (word_to_bytes_f gc.Gc.minor_words) ];
    sum ~name:Process.Runtime.Ocaml.GC.minor_collections
      ~aggregation_temporality:Metrics.Aggregation_temporality_cumulative
      ~is_monotonic:true
      [ int ~now gc.Gc.minor_collections ];
    sum ~name:Process.Runtime.Ocaml.GC.major_collections
      ~aggregation_temporality:Metrics.Aggregation_temporality_cumulative
      ~is_monotonic:true
      [ int ~now gc.Gc.major_collections ];
    sum ~name:Process.Runtime.Ocaml.GC.compactions
      ~aggregation_temporality:Metrics.Aggregation_temporality_cumulative
      ~is_monotonic:true
      [ int ~now gc.Gc.compactions ];
  ]

let setup ?(min_interval_s = default_interval_s)
    ?(meter = Meter_provider.default_meter) () =
  let min_interval_s = max 5 min_interval_s in
  let min_interval = Mtime.Span.(min_interval_s * s) in
  let limiter = Interval_limiter.create ~min_interval () in
  Sdk.add_on_tick_callback (fun () ->
      if Interval_limiter.make_attempt limiter then
        List.iter (Meter.emit1 meter) (get_metrics ()))

let basic_setup () = setup ()
