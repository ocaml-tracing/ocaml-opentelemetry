(** A consumer: pulls signals from a queue, sends them somewhere else *)

open Common_

type error = Export_error.t

(** Number of errors met during export *)
let n_errors = Atomic.make 0

module type IO = Generic_io.S_WITH_CONCURRENCY

(** Generic sender: where to send signals *)
module type SENDER = sig
  module IO : IO

  type t
  (** Sender state *)

  type config

  val create : config:config -> unit -> t

  val cleanup : t -> unit
  (** Cleanup resources once we are done. The sender cannot be used anymore
      after this is called on it *)

  val send : t -> OTEL.Any_signal_l.t -> (unit, error) result IO.t
end

module Make
    (IO : IO)
    (Notifier : Generic_notifier.S with type 'a IO.t = 'a IO.t)
    (Sender : SENDER with type 'a IO.t = 'a IO.t) : sig
  val consumer :
    sender_config:Sender.config ->
    n_workers:int ->
    ticker_task:float option ->
    unit ->
    Consumer.any_signal_l_builder
  (** Make a consumer builder, ie. a builder function that will take a bounded
      queue of signals, and start a consumer to process these signals and send
      them somewhere using HTTP. *)
end = struct
  open IO

  type config = {
    n_workers: int;
    ticker_task: float option;
  }

  type status =
    | Active
    | Shutting_down
    | Stopped

  type state = {
    active: Aswitch.t;  (** Public facing switch *)
    q: OTEL.Any_signal_l.t Bounded_queue.Recv.t;
    status: status Atomic.t;
        (** Internal status, including the shutting down process *)
    notify: Notifier.t;
    n_workers: int Atomic.t;  (** Current number of workers *)
    active_trigger: Aswitch.trigger;
    config: config;
    sender_config: Sender.config;
    m_spans: int Atomic.t;
    m_logs: int Atomic.t;
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
      (* last worker to stop will call [on_done] *)
      ()
    | Active ->
      (* notify potentially asleep workers *)
      Notifier.trigger self.notify;
      Notifier.delete self.notify

  let tick (self : state) =
    if Aswitch.is_on self.active then Notifier.trigger self.notify

  (** Shutdown one worker, when the queue is closed *)
  let shutdown_worker (self : state) : unit =
    if Atomic.fetch_and_add self.n_workers (-1) = 1 then (
      (* we were the last worker, we can shut down the whole consumer *)
      Atomic.set self.status Stopped;
      Aswitch.turn_off self.active_trigger;

      (* sanity check about the queue, which should be drained *)
      let size_q = Bounded_queue.Recv.size self.q in
      if size_q > 0 then
        Printf.eprintf
          "otel: warning: workers exited but work queue still contains %d \
           elements\n\
           %!"
          size_q
    )

  let send_signals (self : state) (sender : Sender.t) ~backoff
      (sigs : OTEL.Any_signal_l.t) : unit IO.t =
    (match sigs with
    | Spans l ->
      ignore (Atomic.fetch_and_add self.m_spans (List.length l) : int)
    | Logs l -> ignore (Atomic.fetch_and_add self.m_logs (List.length l) : int)
    | Metrics _l -> ());

    let* r = Sender.send sender sigs in
    match r with
    | Ok () ->
      Util_net_backoff.on_success backoff;
      IO.return ()
    | Error `Sysbreak ->
      Printf.eprintf "ctrl-c captured, stopping\n%!";
      shutdown self;
      IO.return ()
    | Error err ->
      Atomic.incr n_errors;
      Export_error.report_err err;
      (* avoid crazy error loop *)
      let dur_s = Util_net_backoff.on_error backoff in
      IO.sleep_s (dur_s +. Random.float (dur_s /. 10.))

  let start_worker (self : state) : unit =
    let sender = Sender.create ~config:self.sender_config () in
    let backoff = Util_net_backoff.create () in

    (* loop on [q] *)
    let rec loop () : unit IO.t =
      (* first look at the queue, to drain it *)
      match Bounded_queue.Recv.try_pop self.q with
      | `Closed ->
        (* this worker shuts down, others might still be busy *)
        shutdown_worker self;
        IO.return ()
      | `Item sigs ->
        let* () = send_signals ~backoff self sender sigs in
        loop ()
      | `Empty ->
        (* Printf.eprintf "worker %d: empty queue\n%!" tid; *)
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

    IO.spawn (fun () ->
        IO.protect loop ~finally:(fun () ->
            Sender.cleanup sender;
            IO.return ()))

  let start_ticker (self : state) ~(interval_s : float) : unit =
    let rec loop () : unit IO.t =
      match Atomic.get self.status with
      | Stopped | Shutting_down -> IO.return ()
      | Active ->
        let* () = IO.sleep_s interval_s in
        if Aswitch.is_on self.active then tick self;
        loop ()
    in
    IO.spawn loop

  let create_state ~sender_config ~n_workers ~ticker_task ~q () : state =
    let active, active_trigger = Aswitch.create () in
    let config = { n_workers; ticker_task } in
    let self =
      {
        active;
        active_trigger;
        status = Atomic.make Active;
        n_workers = Atomic.make 0;
        q;
        notify = Notifier.create ();
        config;
        sender_config;
        m_spans = Atomic.make 0;
        m_logs = Atomic.make 0;
      }
    in

    (* start workers *)
    let n_workers = max 2 (min 500 self.config.n_workers) in

    ignore (Atomic.fetch_and_add self.n_workers n_workers : int);
    for _i = 1 to n_workers do
      start_worker self
    done;

    Notifier.register_bounded_queue self.notify q;

    (* start ticker *)
    (match self.config.ticker_task with
    | None -> ()
    | Some interval_s -> start_ticker self ~interval_s);

    self

  let self_metrics ~clock (self : state) : OTEL.Metrics.t list =
    let open OTEL.Metrics in
    let now = OTEL.Clock.now clock in
    let attrs = [ "otel.component.name", `String "otel_ocaml" ] in
    [
      sum ~name:"otel.sdk.exporter.errors" ~is_monotonic:true
        [ int ~now (Atomic.get n_errors) ~attrs ];
      sum ~name:"otel.sdk.exporter.span.exported" ~is_monotonic:true
        [ int ~now (Atomic.get self.m_spans) ~attrs ];
      sum ~name:"otel.sdk.exporter.log.exported" ~is_monotonic:true
        [ int ~now (Atomic.get self.m_logs) ~attrs ];
    ]

  let to_consumer (self : state) : Consumer.t =
    let shutdown () = shutdown self in
    let tick () = tick self in
    let self_metrics ~clock () = self_metrics self ~clock in
    { active = (fun () -> self.active); tick; shutdown; self_metrics }

  let consumer ~sender_config ~n_workers ~ticker_task () :
      Consumer.any_signal_l_builder =
    {
      start_consuming =
        (fun q ->
          let st = create_state ~sender_config ~n_workers ~ticker_task ~q () in
          to_consumer st);
    }
end
