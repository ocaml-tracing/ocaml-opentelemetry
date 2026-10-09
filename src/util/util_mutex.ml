(* Mutex.protect was added in OCaml 5.1, but we support OCaml 4.14 *)
(* cannot inline, otherwise flambda might move code around. (as per Stdlib) *)
let[@inline never] protect m f =
  Mutex.lock m;
  match f () with
  | x ->
    Mutex.unlock m;
    x
  | exception e ->
    (* NOTE: [unlock] does not poll for asynchronous exceptions *)
    Mutex.unlock m;
    Printexc.raise_with_backtrace e (Printexc.get_raw_backtrace ())
