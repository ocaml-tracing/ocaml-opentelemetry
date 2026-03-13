module C = Opentelemetry_client_ocurl_lwt

let () =
  let config1 = C.Config.make () in
  Format.printf "config1: %a\n%!" C.Config.pp config1;
  assert (config1.url_traces = "http://localhost:4318/v1/traces");
  assert (config1.url_metrics = "http://localhost:4318/v1/metrics");
  assert (config1.url_logs = "http://localhost:4318/v1/logs");
  ()

let () =
  let config2 = C.Config.make ~url:"http://example.com:1234" () in
  Format.printf "config2: %a\n%!" C.Config.pp config2;
  assert (config2.url_traces = "http://example.com:1234/v1/traces");
  assert (config2.url_metrics = "http://example.com:1234/v1/metrics");
  assert (config2.url_logs = "http://example.com:1234/v1/logs");
  ()

let () =
  let config3 =
    C.Config.make ~url_traces:"http://example.com/traces"
      ~url_metrics:"http://example.com/metrics"
      ~url_logs:"http://example.com/logs" ()
  in
  Format.printf "config3: %a\n%!" C.Config.pp config3;
  assert (config3.url_traces = "http://example.com/traces");
  assert (config3.url_metrics = "http://example.com/metrics");
  assert (config3.url_logs = "http://example.com/logs");
  ()

let () = print_endline "All URL tests passed"
