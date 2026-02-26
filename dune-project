(lang dune 2.9)

(name opentelemetry)

(generate_opam_files true)

(source
 (github imandra-ai/ocaml-opentelemetry))

(version 0.12)

(authors "the Imandra team and contributors")

(maintainers
 "Simon Cruanes <simon.cruanes.2007@m4x.org>"
 "Matt Bray <mattjbray@gmail.com>"
 "ELLIOTTCABLE <opam@ell.io>")

(license MIT)

;(documentation https://url/to/documentation)

(package
 (name opentelemetry)
 (synopsis "Instrumentation for https://opentelemetry.io")
 (depends
  (ocaml
   (>= "4.08"))
  ptime
  hmap
  atomic
  (thread-local-storage
   (and
    (>= 0.2)
    (< 0.3)))
  (odoc :with-doc)
  (alcotest :with-test)
  (pbrt
   (and
    (>= 3.0)
    (< 4.0)))
  (ocaml-lsp-server :with-dev-setup)
  (ambient-context
   (and
    (>= 0.2)
    (< 0.3)))
  (ocamlformat
   (and
    :with-dev-setup
    (>= 0.27)
    (< 0.28))))
 (depopts trace lwt eio)
 (conflicts
  (trace
   (< 0.11)))
 (tags
  (instrumentation tracing opentelemetry datadog jaeger)))

(package
 (name opentelemetry-lwt)
 (synopsis "Lwt-compatible instrumentation for https://opentelemetry.io")
 (depends
  (ocaml
   (>= "4.08"))
  (opentelemetry
   (= :version))
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
  (odoc :with-doc)
  (ezcurl
   (and
    (>= 0.3)
    (< 0.4)))
  ocurl
  (alcotest :with-test))
 (synopsis "Collector client for opentelemetry, using http + ezcurl"))

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
  (alcotest :with-test))
 (synopsis "Opentelemetry tracing for Cohttp HTTP servers"))

(package
 (name opentelemetry-cohttp-lwt)
 (depends
  (ocaml
   (>= "4.08"))
  (opentelemetry
   (= :version))
  (opentelemetry-lwt
   (= :version))
  (odoc :with-doc)
  (lwt
   (>= "5.3"))
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
  (odoc :with-doc)
  (lwt
   (>= "5.3"))
  (lwt_ppx
   (>= "2.0"))
  cohttp-lwt
  cohttp-lwt-unix
  (alcotest :with-test)
  (containers :with-test))
 (synopsis "Collector client for opentelemetry, using cohttp + lwt"))

(package
 (name opentelemetry-client-cohttp-eio)
 (depends
  (ocaml
   (>= "5.00"))
  (mtime
   (>= "1.4"))
  ca-certs
  mirage-crypto-rng-eio
  (opentelemetry
   (= :version))
  (odoc :with-doc)
  (cohttp-eio
   (>= 6.1.0))
  (eio_main :with-test)
  tls-eio
  (alcotest :with-test)
  (containers :with-test))
 (synopsis "Collector client for opentelemetry, using cohttp + eio"))
