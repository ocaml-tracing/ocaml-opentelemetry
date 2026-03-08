(lang dune 2.9)

(name opentelemetry)

(generate_opam_files true)

(source
 (github imandra-ai/ocaml-opentelemetry))

(version 0.12)

(implicit_transitive_deps false)

(authors "the Imandra team and contributors")

(maintainers
 "Simon Cruanes <simon.cruanes.2007@m4x.org>"
 "Matt Bray <mattjbray@gmail.com>"
 "ELLIOTTCABLE <opam@ell.io>")

(license MIT)

;(documentation https://url/to/documentation)

(package
 (name opentelemetry)
 (synopsis "Core library for instrumentation and serialization for https://opentelemetry.io")
 (depends
  (ocaml
   (>= "4.08"))
  ptime
  hmap
  (odoc :with-doc)
  (alcotest :with-test)
  (pbrt
   (and
    (>= 4.0)
    (< 5.0)))
  (pbrt_yojson
   (and
    (>= 4.0)
    (< 5.0)))
  (ambient-context
   (>= 0.2))
  (ocaml-lsp-server :with-dev-setup)
  (ocamlformat
   (and
    :with-dev-setup
    (>= 0.27)
    (< 0.28)))
  (mtime
   (>= "1.4")))
 (depopts atomic trace thread-local-storage lwt eio picos)
 (conflicts
  (trace
   (< 0.12)))
 (tags
  (instrumentation tracing opentelemetry datadog jaeger)))

(package
 (name opentelemetry-client)
 (synopsis "Client SDK for https://opentelemetry.io")
 (depends
  (opentelemetry
   (= :version))
  (odoc :with-doc)
  (alcotest :with-test)
  (thread-local-storage
   (and
    (>= 0.2)
    (< 0.3))))
 (tags
  (tracing opentelemetry sdk)))

(package
 (name opentelemetry-lwt)
 (synopsis "Lwt-compatible instrumentation for https://opentelemetry.io")
 (depends
  (ocaml
   (>= "4.08"))
  (opentelemetry
   (= :version))
  ambient-context-lwt
  (cohttp-lwt-unix :with-test)
  (odoc :with-doc)
  (lwt
   (>= "5.3"))
  (lwt_ppx
   (>= "2.0"))
  (alcotest :with-test))
 (tags
  (instrumentation tracing opentelemetry datadog lwt)))

(package
 (name opentelemetry-client-ocurl)
 (depends
  (ocaml
   (>= "4.08"))
  (mtime
   (>= "1.4"))
  ; for spans
  ; atomic ; vendored
  (opentelemetry
   (= :version))
  (opentelemetry-client
   (= :version))
  (odoc :with-doc)
  (ezcurl
   (>= 0.2.3))
  ocurl
  (alcotest :with-test))
 (synopsis "Collector client for opentelemetry, using http + ezcurl"))

(package
 (name opentelemetry-client-ocurl-lwt)
 (depends
  (ocaml
   (>= "4.08"))
  (mtime
   (>= "1.4"))
  (opentelemetry
   (= :version))
  (opentelemetry-client
   (= :version))
  (odoc :with-doc)
  (ezcurl-lwt
   (>= 0.2.3))
  ocurl
  (lwt
   (>= "5.3"))
  (lwt_ppx
   (>= "2.0"))
  (alcotest :with-test))
 (synopsis "Collector client for opentelemetry, using ezcurl-lwt"))

(package
 (name opentelemetry-logs)
 (depends
  (ocaml
   (>= "4.08"))
  (opentelemetry
   (= :version))
  (odoc :with-doc)
  (logs
   (>= "0.7.0"))
  (alcotest :with-test)
  (containers :with-test)
  (cohttp-lwt-unix :with-test)
  (opentelemetry-client-cohttp-lwt
   (and
    :with-test
    (= :version)))
  (opentelemetry-cohttp-lwt
   (and
    :with-test
    (= :version))))
 (synopsis "Opentelemetry-based reporter for Logs"))

(package
 (name opentelemetry-cohttp-lwt)
 (depends
  (ocaml
   (>= "4.08"))
  (opentelemetry
   (= :version))
  (opentelemetry-lwt
   (= :version))
  ambient-context-lwt
  (odoc :with-doc)
  (lwt
   (>= "5.3"))
  (cohttp
   (>= "6.0.0"))
  (cohttp-lwt
   (>= "6.0.0"))
  (alcotest :with-test))
 (synopsis "Opentelemetry tracing for Cohttp HTTP servers"))

(package
 (name opentelemetry-client-cohttp-lwt)
 (depends
  (ocaml
   (>= "4.08"))
  (mtime
   (>= "1.4"))
  ; for spans
  (opentelemetry
   (= :version))
  (opentelemetry-client
   (= :version))
  (opentelemetry-lwt
   (= :version))
  ambient-context-lwt
  (odoc :with-doc)
  (lwt
   (>= "5.3"))
  (lwt_ppx
   (>= "2.0"))
  cohttp-lwt
  cohttp-lwt-unix
  (alcotest :with-test)
  (containers :with-test)
  (opentelemetry-lwt
   (and
    :with-test
    (= :version))))
 (synopsis "Collector client for opentelemetry, using cohttp + lwt"))

(package
 (name opentelemetry-client-cohttp-eio)
 (depends
  (ocaml
   (>= "5.00"))
  (mtime
   (>= "1.4"))
  ca-certs
  mirage-crypto-rng
  ambient-context-eio
  (opentelemetry
   (= :version))
  (opentelemetry-client
   (= :version))
  (odoc :with-doc)
  (cohttp-eio
   (>= 6.1.0))
  (eio_main :with-test)
  (tls-eio
   (>= 2.0.1))
  (alcotest :with-test)
  (containers :with-test)
  (cohttp-lwt-unix :with-test))
 (synopsis "Collector client for opentelemetry, using cohttp + eio"))
