open Common_

(** Shutdown this exporter and block the thread until it's done.

    With the new Exporter.t interface, shutdown is synchronous. This function is
    kept for backwards compatibility. *)
let shutdown (exp : OTEL.Exporter.t) : unit = OTEL.Exporter.shutdown exp

(** Shutdown main exporter and wait *)
let shutdown_main () : unit = Option.iter shutdown (OTEL.Sdk.get ())
