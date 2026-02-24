(** Build an exporter from a queue and a consumer.

    The exporter will send signals into the queue (possibly dropping them if the
    queue is full), and the consumer is responsible for actually exporting the
    signals it reads from the other end of the queue.

    At shutdown time, the queue is closed for writing, but only once it's empty
    will the consumer properly shutdown. *)

open Common_
module BQ = Bounded_queue

(** Pair a queue with a consumer to build an exporter.

    The resulting exporter will emit logs, spans, and traces directly into the
    bounded queue; while the consumer takes them from the queue to forward them
    somewhere else, store them, etc.
    @param resource_attributes attributes added to every "resource" batch *)
let create ~clock ~(q : OTEL.Any_signal_l.t Bounded_queue.t)
    ~(consumer : Consumer.any_signal_l_builder) () : OTEL.Exporter.t =
  let shutdown_started = Atomic.make false in
  let active, trigger = Aswitch.create () in
  let consumer = consumer.start_consuming q.recv in

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

  let export (sig_ : OTEL.Any_signal_l.t) =
    if Aswitch.is_on active then BQ.Send.push q.send [ sig_ ]
  in

  let shutdown () =
    if Aswitch.is_on active && not (Atomic.exchange shutdown_started true) then (
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

  { OTEL.Exporter.export; active = (fun () -> active); self_metrics; shutdown }
