(** A consumer that just calls another exporter.

    This is useful to introduce queueing behavior using {!Exporter_queued}, but
    simply forwarding to another (presumably non-queue) exporter.

    It is generic because we need some sort of threading/concurrency to run the
    consumer. *)

open Common_

module type IO = Generic_io.S_WITH_CONCURRENCY

module Make
    (IO : IO)
    (Notifier : Generic_notifier.S with type 'a IO.t = 'a IO.t) : sig
  val consumer : OTEL.Exporter.t -> OTEL.Any_signal_l.t Consumer.Builder.t
end = struct
  open IO

  type status =
    | Active
    | Shutting_down
    | Stopped

  type state = {
    active: Aswitch.t;  (** Public facing switch *)
    active_trigger: Aswitch.trigger;
    status: status Atomic.t;  (** Internal state, including shutdown *)
    q: OTEL.Any_signal_l.t Bounded_queue.Recv.t;
    notify: Notifier.t;
    exp: OTEL.Exporter.t;
  }

  let shutdown self : unit =
    let old_status =
      Util_atomic.update_cas self.status @@ fun status ->
      match status with
      | Stopped -> status, status
      | Shutting_down -> status, status
      | Active -> status, Shutting_down
    in

    match old_status with
    | Stopped -> ()
    | Shutting_down ->
      (* when the worker stops it will call [on_done] *)
      ()
    | Active ->
      (* notify potentially asleep workers *)
      Notifier.trigger self.notify;
      Notifier.delete self.notify

  let tick (self : state) = Notifier.trigger self.notify

  (** Shutdown worker *)
  let shutdown_worker (self : state) : unit =
    (* only one worker, so, turn off exporter *)
    OTEL.Exporter.shutdown self.exp;

    (* and we are shut down! *)
    Atomic.set self.status Stopped;
    Aswitch.turn_off self.active_trigger

  let start_worker (self : state) : unit =
    (* loop on [q] *)
    let rec loop () : unit IO.t =
      match Bounded_queue.Recv.try_pop self.q with
      | `Closed ->
        shutdown_worker self;
        IO.return ()
      | `Item sig_ ->
        self.exp.OTEL.Exporter.export sig_;
        loop ()
      | `Empty ->
        (match Atomic.get self.status with
        | Stopped ->
          assert false
          (* shouldn't happen without us going through [Shutting_down] *)
        | Shutting_down ->
          shutdown_worker self;
          IO.return ()
        | Active ->
          let* () =
            Notifier.wait self.notify ~should_keep_waiting:(fun () ->
                Bounded_queue.Recv.size self.q = 0
                && Atomic.get self.status = Active)
          in
          loop ())
    in

    IO.spawn loop

  let create_state ~q ~exporter () : state =
    let active, active_trigger = Aswitch.create () in
    let self =
      {
        active;
        active_trigger;
        status = Atomic.make Active;
        q;
        exp = exporter;
        notify = Notifier.create ();
      }
    in

    start_worker self;
    self

  let self_metrics (self : state) ~clock : OTEL.Metrics.t list =
    let open OTEL.Metrics in
    let now = OTEL.Clock.now clock in
    [
      sum ~name:"otel_ocaml.export.batches_discarded_by_bounded_queue"
        ~is_monotonic:true
        [ int ~now (Bounded_queue.Recv.num_discarded self.q) ];
    ]

  let to_consumer (self : state) : Consumer.t =
    let shutdown () = shutdown self in
    let tick () = tick self in
    let self_metrics ~clock () = self_metrics self ~clock in
    { active = (fun () -> self.active); tick; shutdown; self_metrics }

  let consumer exporter : _ Consumer.Builder.t =
    {
      start_consuming =
        (fun q ->
          let st = create_state ~q ~exporter () in
          to_consumer st);
    }
end
