open Opentelemetry_emitter

(** Emit current batch, if the conditions are met *)
let maybe_emit_ (b : _ Batch.t) ~(e : _ Emitter.t) ~mtime : unit =
  match Batch.pop_if_ready b ~force:false ~mtime with
  | None -> ()
  | Some l -> Emitter.emit e l

let wrap_emitter_with_batch (self : _ Batch.t) (e : _ Emitter.t) : _ Emitter.t =
  (* we need to be able to close this emitter before we close [e]. This
     will become [true] when we close, then we call [Emitter.flush_and_close e],
     then [e] itself will be closed. *)
  let closed_here = Atomic.make false in

  let signal_name = e.signal_name in
  let enabled () = (not (Atomic.get closed_here)) && e.enabled () in
  let closed () = Atomic.get closed_here || e.closed () in

  let dropped_name = Printf.sprintf "otel.sdk.%s.batch.dropped" signal_name in
  let self_metrics ~now () =
    let m =
      Opentelemetry_core.Metrics.(
        sum ~name:dropped_name [ int ~now (Batch.n_dropped self) ])
    in
    m :: e.self_metrics ~now ()
  in
  let flush_and_close () =
    if not (Atomic.exchange closed_here true) then (
      (* NOTE: we need to close this wrapping emitter first, to prevent
         further pushes; then write the content to [e]; then
         flusn and close [e]. In this order. *)
      (match
         Batch.pop_if_ready self ~force:true ~mtime:Batch.Internal_.mtime_dummy_
       with
      | None -> ()
      | Some l -> Emitter.emit e l);

      (* now we can close [e], nothing remains in [self] *)
      Emitter.flush_and_close e
    )
  in

  let tick ~mtime =
    if not (Atomic.get closed_here) then (
      (* first, check if batch has timed out *)
      maybe_emit_ self ~e ~mtime;

      (* only then, tick the underlying emitter *)
      Emitter.tick e ~mtime
    )
  in

  let emit l =
    if l <> [] && not (Atomic.get closed_here) then (
      (* Printf.eprintf "otel.batch.add %d items\n%!" (List.length l); *)
      Batch.push' self l;

      (* we only check for size here, not for timeout. The [tick] function is
         enough for timeouts, whereas [emit] is in the hot path of every single
         span/metric/log *)
      maybe_emit_ self ~e ~mtime:Batch.Internal_.mtime_dummy_
    )
  in

  {
    Emitter.closed;
    signal_name;
    self_metrics;
    enabled;
    flush_and_close;
    tick;
    emit;
  }

let add_batching ~timeout ~batch_size (emitter : 'a Emitter.t) : 'a Emitter.t =
  let b = Batch.make ~batch:batch_size ~timeout () in
  wrap_emitter_with_batch b emitter

let add_batching_opt ~timeout ~batch_size:(b : int option) e =
  match b with
  | None -> e
  | Some b -> add_batching ~timeout ~batch_size:b e
