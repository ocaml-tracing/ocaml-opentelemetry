open Common_

type t = { cbs: (unit -> Metrics.t list) Alist.t } [@@unboxed]

let create () : t = { cbs = Alist.make () }

let[@inline] add_metrics_cb (self : t) f = Alist.add self.cbs f

let minimum_min_interval = Mtime.Span.(100 * ms)

let collect_and_send (self : t) (exp : Exporter.t) =
  (* collect all metrics *)
  let res = ref [] in
  List.iter
    (fun f ->
      let f_metrics = f () in
      res := List.rev_append f_metrics !res)
    (Alist.get self.cbs);
  let metrics = !res in

  (* emit the metrics *)
  Exporter.send_metrics exp metrics

let add_to_exporter ?(min_interval = Mtime.Span.(4 * s)) (exp : Exporter.t)
    (self : t) =
  let min_interval =
    Mtime.Span.(
      if is_shorter min_interval ~than:minimum_min_interval then
        minimum_min_interval
      else
        min_interval)
  in

  let limiter = Interval_limiter.create ~min_interval () in
  let on_tick () =
    if Interval_limiter.make_attempt limiter then collect_and_send self exp
  in
  Exporter.on_tick exp on_tick

let with_set_added_to_exporter ?min_interval (exp : Exporter.t) (f : t -> 'a) :
    'a =
  let set = create () in
  add_to_exporter ?min_interval exp set;
  f set

let with_set_added_to_main_exporter ?min_interval (f : t -> unit) : unit =
  match Main_exporter.get () with
  | None -> ()
  | Some exp -> with_set_added_to_exporter ?min_interval exp f

module Main_set = struct
  let cur_set_ : t option Atomic.t = Atomic.make None

  let rec get () : t =
    match Atomic.get cur_set_ with
    | Some s -> s
    | None ->
      let s = create () in
      if Atomic.compare_and_set cur_set_ None (Some s) then (
        (match Main_exporter.get () with
        | Some exp -> add_to_exporter exp s
        | None -> ());
        s
      ) else
        get ()
end
