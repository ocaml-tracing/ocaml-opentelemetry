type t = unit -> Key_value.t list
(** A dynamic enricher is a callback that produces high-cardinality attributes
    at span/log-record creation time. This enables "wide events". *)

open struct
  let enrichers_ : t Alist.t = Alist.make ()
end

let add (f : t) : unit = Alist.add enrichers_ f

let collect () : Key_value.t list =
  let acc = ref [] in
  List.iter
    (fun f ->
      match f () with
      | kvs -> acc := List.rev_append kvs !acc
      | exception exn ->
        let bt = Printexc.get_raw_backtrace () in
        Printf.eprintf "opentelemetry: dynamic_enricher raised %s\n%s%!"
          (Printexc.to_string exn)
          (Printexc.raw_backtrace_to_string bt))
    (Alist.get enrichers_);
  !acc
