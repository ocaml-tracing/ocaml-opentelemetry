open Opentelemetry_emitter

let add_sampler (self : Sampler.t) (e : _ Emitter.t) : _ Emitter.t =
  let signal_name = e.signal_name in
  let enabled () = e.enabled () in
  let closed () = Emitter.closed e in
  let flush_and_close () = Emitter.flush_and_close e in
  let tick ~mtime = Emitter.tick e ~mtime in

  let m_rate = Printf.sprintf "otel.sdk.%s.sampler.actual-rate" signal_name in
  let self_metrics ~now () =
    Opentelemetry_core.Metrics.(
      gauge ~name:m_rate [ float ~now (Sampler.actual_rate self) ])
    :: e.self_metrics ~now ()
  in

  let emit l =
    if l <> [] && e.enabled () then (
      let accepted = List.filter (fun _x -> Sampler.accept self) l in
      if accepted <> [] then Emitter.emit e accepted
    )
  in

  {
    Emitter.closed;
    self_metrics;
    signal_name;
    enabled;
    flush_and_close;
    tick;
    emit;
  }

let sample ~proba_accept e = add_sampler (Sampler.create ~proba_accept ()) e
