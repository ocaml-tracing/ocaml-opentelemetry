
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

include deps/Makefile.ci

VERSION=$(shell awk '/^version:/ {print $$2}' opentelemetry.opam)
update_next_tag:
	@echo "update version to $(VERSION)..."
	sed -i "s/NEXT_VERSION/$(VERSION)/g" $(wildcard src/**/*.ml) $(wildcard src/**/*.mli)
	sed -i "s/NEXT_RELEASE/$(VERSION)/g" $(wildcard src/*.ml) $(wildcard src/**/*.ml) $(wildcard src/*.mli) $(wildcard src/**/*.mli)
