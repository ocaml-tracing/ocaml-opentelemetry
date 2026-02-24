(** Combine multiple exporters into one *)

open Common_

let combine_l (es : OTEL.Exporter.t list) : OTEL.Exporter.t =
  match es with
  | [] -> OTEL.Exporter.dummy ()
  | _ ->
    (* active turns off once all constituent exporters are off *)
    let active, trigger = Aswitch.create () in
    let remaining = Atomic.make (List.length es) in
    List.iter
      (fun e ->
        Aswitch.on_turn_off (OTEL.Exporter.active e) (fun () ->
            if Atomic.fetch_and_add remaining (-1) = 1 then
              Aswitch.turn_off trigger))
      es;
    {
      OTEL.Exporter.export =
        (fun sig_ -> List.iter (fun e -> e.OTEL.Exporter.export sig_) es);
      active = (fun () -> active);
      shutdown = (fun () -> List.iter OTEL.Exporter.shutdown es);
      self_metrics =
        (fun () ->
          List.concat_map (fun e -> e.OTEL.Exporter.self_metrics ()) es);
    }

(** [combine exp1 exp2] is the exporter that emits signals to both [exp1] and
    [exp2]. *)
let combine exp1 exp2 : OTEL.Exporter.t = combine_l [ exp1; exp2 ]
