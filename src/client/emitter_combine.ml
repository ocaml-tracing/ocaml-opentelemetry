(** Combine multiple emitters into one. *)

open Opentelemetry_emitter.Emitter

type closing_behavior =
  [ `Close_when_all_closed
  | `Close_when_one_closed
  ]
(** When to close the combined emitter:

    - [`Close_when_all_closed]: closed when all the emitters that are combined
      are closed
    - [`Close_when_one_closed]: closed as soon as one of the emitters is closed
*)

(** [combine_l es] is an emitter that sends signals to every emitter in [es].
    @param closing
      when is this emitter closing. Default [`Close_when_all_closed]. *)
let combine_l ?(closing : closing_behavior = `Close_when_all_closed)
    (es : 'a t list) : 'a t =
  assert (es <> []);
  let signal_name = (List.hd es).signal_name in
  let closed =
   fun () ->
    match closing with
    | `Close_when_all_closed -> List.for_all closed es
    | `Close_when_one_closed -> List.exists closed es
  in
  let self_metrics ~now () =
    List.flatten @@ List.map (fun e -> e.self_metrics ~now ()) es
  in
  let enabled () = not (closed ()) in
  let emit x = if x <> [] then List.iter (fun e -> emit e x) es in
  let tick ~mtime = List.iter (tick ~mtime) es in
  let flush_and_close () = List.iter flush_and_close es in
  { signal_name; self_metrics; closed; enabled; emit; tick; flush_and_close }

let combine_l ?closing es : _ t =
  match es with
  | [] -> dummy
  | _ -> combine_l ?closing es

let combine e1 e2 : _ t = combine_l [ e1; e2 ]
