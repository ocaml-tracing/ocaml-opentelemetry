(** Build an exporter from a queue and a consumer.

    The exporter will send signals into the queue (possibly dropping them if the
    queue is full), and the consumer is responsible for actually exporting the
    signals it reads from the other end of the queue.

    At shutdown time, the queue is closed for writing, but only once it's empty
    will the consumer properly shutdown. *)

open Common_
module BQ = Bounded_queue

module BQ_emitters = struct
  (* NOTE: these emitters, when closed, don't close the bounded
     queue because we need to flush_and_close the other emitters first.
     The bounded queue is a shared resource. *)

  let logs_emitter_of_bq (q : OTEL.Any_signal_l.t Bounded_queue.Send.t) :
      _ OTEL.Emitter.t =
    Bounded_queue.Send.to_emitter q ~signal_name:"logs"
      ~close_queue_on_close:false
    |> Opentelemetry_emitter.Emitter.flat_map OTEL.Any_signal_l.of_logs_or_empty

  let spans_emitter_of_bq (q : OTEL.Any_signal_l.t Bounded_queue.Send.t) :
      _ OTEL.Emitter.t =
    Bounded_queue.Send.to_emitter q ~signal_name:"spans"
      ~close_queue_on_close:false
    |> Opentelemetry_emitter.Emitter.flat_map
         OTEL.Any_signal_l.of_spans_or_empty

  let metrics_emitter_of_bq (q : OTEL.Any_signal_l.t Bounded_queue.Send.t) :
      _ OTEL.Emitter.t =
    Bounded_queue.Send.to_emitter q ~signal_name:"metrics"
      ~close_queue_on_close:false
    |> Opentelemetry_emitter.Emitter.flat_map
         OTEL.Any_signal_l.of_metrics_or_empty
end

(** Pair a queue with a consumer to build an exporter.

    The resulting exporter will emit logs, spans, and traces directly into the
    bounded queue; while the consumer takes them from the queue to forward them
    somewhere else, store them, etc.
    @param resource_attributes attributes added to every "resource" batch *)
let create ~clock ~(q : OTEL.Any_signal_l.t Bounded_queue.t)
    ~(consumer : Consumer.any_signal_l_builder) () : OTEL.Exporter.t =
  let open Opentelemetry_emitter in
  let shutdown_started = Atomic.make false in
  let active, trigger = Aswitch.create () in
  let consumer = consumer.start_consuming q.recv in

  let emit_spans = BQ_emitters.spans_emitter_of_bq q.send in
  let emit_logs = BQ_emitters.logs_emitter_of_bq q.send in
  let emit_metrics = BQ_emitters.metrics_emitter_of_bq q.send in

  let tick_set = Cb_set.create () in
  let tick () = Cb_set.trigger tick_set in
  let on_tick f = Cb_set.register tick_set f in

  let self_metrics () : _ list =
    let now = OTEL.Clock.now clock in
    let m_size =
      OTEL.Metrics.gauge ~name:"otel.sdk.exporter.queue.size"
        [ OTEL.Metrics.int ~now (Bounded_queue.Recv.size q.recv) ]
    and m_cap =
      OTEL.Metrics.gauge ~name:"otel.sdk.exporter.queue.capacity"
        [ OTEL.Metrics.int ~now (Bounded_queue.Recv.high_watermark q.recv) ]
    and m_discarded =
      OTEL.Metrics.sum ~is_monotonic:true
        ~name:"otel.sdk.exporter_queue.discarded"
        [ OTEL.Metrics.int ~now (Bounded_queue.Recv.num_discarded q.recv) ]
    in
    m_size :: m_cap :: m_discarded :: Consumer.self_metrics consumer ~clock
  in

  let shutdown () =
    if Aswitch.is_on active && not (Atomic.exchange shutdown_started true) then (
      (* flush all emitters *)
      Emitter.flush_and_close emit_spans;
      Emitter.flush_and_close emit_logs;
      Emitter.flush_and_close emit_metrics;

      (* first, prevent further pushes to the queue. Consumer workers
       can still drain it. *)
      Bounded_queue.Send.close q.send;

      (* shutdown consumer; once it's down it'll turn our switch off too *)
      Aswitch.link (Consumer.active consumer) trigger;
      Consumer.shutdown consumer
    )
  in

  (* if consumer shuts down for some reason, we also must *)
  Aswitch.on_turn_off (Consumer.active consumer) shutdown;

  let active () = active in
  {
    active;
    clock;
    emit_logs;
    emit_metrics;
    emit_spans;
    self_metrics;
    tick;
    on_tick;
    shutdown;
  }
