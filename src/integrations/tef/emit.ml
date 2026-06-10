(** Emit a {!Convert.bundle} through the application's globally-configured
    OpenTelemetry providers.

    This routes spans/metrics to whatever exporter the application has set up
    (e.g. [opentelemetry-client-ocurl]); if no exporter is configured the
    signals are simply dropped. For a self-contained sender that does not rely
    on the global providers, see {!Curl_export}. *)

let via_providers (b : Convert.bundle) : unit =
  List.iter Opentelemetry.Trace_provider.emit b.Convert.spans;
  if b.Convert.metrics <> [] then
    Opentelemetry.Meter_provider.emit_l b.Convert.metrics
