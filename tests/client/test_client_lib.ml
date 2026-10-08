open Alcotest
module Config = Opentelemetry_client.Http_config

let test_config_printing () =
  let module Env = Config.Env () in
  let actual =
    Format.asprintf "%a" Config.pp @@ Env.make (fun common () -> common) ()
  in
  let expected =
    "{ debug=false; log_level=info; sdk_disabled=false; self_trace=false;\n\
    \ self_metrics=false; url_traces=\"http://localhost:4318/v1/traces\";\n\
    \ url_metrics=\"http://localhost:4318/v1/metrics\";\n\
    \ url_logs=\"http://localhost:4318/v1/logs\"; headers=[]; headers_traces=[];\n\
    \ headers_metrics=[]; headers_logs=[]; protocol=http/protobuf;\n\
    \ timeout_ms=10000; timeout_traces_ms=10000; timeout_metrics_ms=10000;\n\
    \ timeout_logs_ms=10000; traces={batch=400; timeout=2s}; metrics={batch=200;\n\
    \ timeout=2s}; logs={batch=400; timeout=2s}; http_concurrency_level=None;\n\
    \ retry_max_attempts=3; retry_initial_delay_ms=100; retry_max_delay_ms=5000;\n\
    \ retry_backoff_multiplier=2.0; sampler=parentbased(always_on) }"
  in
  check' string ~msg:"is rendered correctly" ~actual ~expected

let suite =
  [ test_case "default config pretty printing" `Quick test_config_printing ]

let () = Alcotest.run "Opentelemetry_client" [ "Config", suite ]
