include Opentelemetry

(** Setup Lwt as the ambient context *)
let setup_ambient_context () =
  Opentelemetry_ambient_context.set_current_storage Ambient_context_lwt.storage

module Sdk = struct
  include Sdk

  let remove () : unit Lwt.t =
    let p, resolve = Lwt.wait () in
    remove () ~on_done:(fun () -> Lwt.wakeup_later resolve ());
    p
end

external reraise : exn -> 'a = "%reraise"
(** This is equivalent to [Lwt.reraise]. We inline it here so we don't force to
    use Lwt's latest version *)

module Tracer = struct
  include Tracer

  (** Sync span guard *)
  let with_ (type a) ?(tracer = default) ?force_new_trace_id ?trace_state ?attrs
      ?kind ?trace_id ?parent ?links name (cb : Span.t -> a Lwt.t) : a Lwt.t =
    let open Lwt.Syntax in
    let thunk, finally =
      with_thunk_and_finally tracer ?force_new_trace_id ?trace_state ?attrs
        ?kind ?trace_id ?parent ?links name cb
    in

    let* r =
      Lwt.catch
        (fun () ->
          let+ res = thunk () in
          Ok res)
        (fun exn ->
          let bt = Printexc.get_raw_backtrace () in
          Lwt.return (Error (exn, bt)))
    in

    match r with
    | Ok r ->
      finally (Ok ());
      Lwt.return r
    | Error (exn, bt) ->
      finally (Error (exn, bt));
      Lwt.fail exn
end

module Trace = Tracer [@@deprecated "use Tracer"]

module Metrics = struct
  include Metrics
end

module Logs = struct
  include Proto.Logs
  include Log_record
  include Logger
end
