
OPTS=--profile=release --ignore-promoted-rules

all:
	@dune build @all $(OPTS)

test:
	@dune runtest --force $(OPTS)

clean:
	@dune clean

protoc-gen:
	FORCE_GENPROTO=true dune build @lint

update-submodules:
	git submodule update --init

doc:
	@dune build @doc

PACKAGES=$(shell opam show . -f name)
odig-doc:
	@odig odoc --cache-dir=_doc/ $(PACKAGES)

format:
	@dune build @fmt --auto-promote

format-check:
	@dune build $(DUNE_OPTS) @fmt --display=quiet

setup-githooks:
	uvx pre-commit install --hook-type pre-push

WATCH ?= @all
watch:
	@dune build $(WATCH) -w $(OPTS)

# --- CI Docker images ---
CI_REGISTRY = ghcr.io/ocaml-tracing/ocaml-opentelemetry
CI_VERSIONS = 4.08 4.14 5.4

build-ci-docker:
	@for v in $(CI_VERSIONS); do \
		docker build -f deps/dockerfile.$$v -t $(CI_REGISTRY)/ci-$$v:latest . ; \
	done

upload-ci-docker: build-ci-docker
	@for v in $(CI_VERSIONS); do \
		docker push $(CI_REGISTRY)/ci-$$v:latest ; \
	done || ( echo  "to login:  docker login ghcr.io -u <your-github-username>" ; exit 1 )

VERSION=$(shell awk '/^version:/ {print $$2}' opentelemetry.opam)
update_next_tag:
	@echo "update version to $(VERSION)..."
	sed -i "s/NEXT_VERSION/$(VERSION)/g" $(wildcard src/**/*.ml) $(wildcard src/**/*.mli)
	sed -i "s/NEXT_RELEASE/$(VERSION)/g" $(wildcard src/*.ml) $(wildcard src/**/*.ml) $(wildcard src/*.mli) $(wildcard src/**/*.mli)
