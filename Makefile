# OASIS_START
# DO NOT EDIT (digest: 4c293511860bb966e727ba6f0ecc8197)

SETUP = ./setup.exe

build: setup.data $(SETUP)
	$(SETUP) -build $(BUILDFLAGS)

doc: setup.data $(SETUP) build
	$(SETUP) -doc $(DOCFLAGS)

test: setup.data $(SETUP) build
	$(SETUP) -test $(TESTFLAGS)

all: $(SETUP)
	$(SETUP) -all $(ALLFLAGS)

install: setup.data $(SETUP)
	$(SETUP) -install $(INSTALLFLAGS)

uninstall: setup.data $(SETUP)
	$(SETUP) -uninstall $(UNINSTALLFLAGS)

reinstall: setup.data $(SETUP)
	$(SETUP) -reinstall $(REINSTALLFLAGS)

clean: $(SETUP)
	$(SETUP) -clean $(CLEANFLAGS)

distclean: $(SETUP)
	$(SETUP) -distclean $(DISTCLEANFLAGS)
	$(RM) $(SETUP)

setup.data: $(SETUP)
	$(SETUP) -configure $(CONFIGUREFLAGS)

configure: $(SETUP)
	$(SETUP) -configure $(CONFIGUREFLAGS)

setup.exe: setup.ml _oasis
	ocamlfind ocamlopt -o $@ -linkpkg -package oasis.dynrun setup.ml || ocamlfind ocamlc -o $@ -linkpkg -package oasis.dynrun setup.ml || true
	$(RM) setup.cmi setup.cmo setup.cmx setup.o

.PHONY: build doc test all install uninstall reinstall clean distclean configure

# OASIS_STOP

rst_doc:
	@echo "build Sphinx documentation (into _build/doc)"
	sphinx-build doc _build/doc
	mkdir -p gh-pages/rst/
	cp -r _build/doc/*.html _build/doc/*.js _build/doc/_static gh-pages/rst

open_doc: rst_doc
	firefox _build/doc/contents.html

push_doc: doc rst_doc
	rsync -tavu logtk.docdir/* cedeela.fr:~/simon/root/software/logtk/
	rsync -tavu _build/doc/* cedeela.fr:~/simon/root/software/logtk/rst/

test-all: build
	./run_tests.native --verbose
	# ./tests/quick/all.sh # FIXME?

INTERFACE_FILES = $(shell find src -name '*.mli')
IMPLEMENTATION_FILES = $(shell find src -name '*.ml')
VERSION=$(shell awk '/^Version:/ {print $$2}' _oasis)

update_next_tag:
	@echo "update version to $(VERSION)..."
	zsh -c 'sed -i "s/NEXT_VERSION/$(VERSION)/g" src/**/*.ml{,i}(.)'
	zsh -c 'sed -i "s/NEXT_RELEASE/$(VERSION)/g" src/**/*.ml{,i}(.)'

tags:
	otags $(IMPLEMENTATION_FILES) $(INTERFACE_FILES)

dot:
	for i in *.dot; do dot -Tsvg "$$i" > "$$( basename $$i .dot )".svg; done

TEST_FILES = tests/ examples/

frogtest:
	frogtest run -c ./tests/conf.toml $(TEST_FILES)

frogtest-zipper:
	frogtest run -p zipperposition -c ./tests/conf.toml $(TEST_FILES)

frogtest-hornet:
	frogtest run -p hornet -c ./tests/conf.toml $(TEST_FILES)

frogtest-tip:
	@[ -d tip-benchmarks ] || (echo "missing tip-benchmarks/" && exit 1)
	frogtest run --meta=`git rev-parse HEAD` \
	  -c ./tip-benchmarks/conf.toml

BENCH_DIR="bench-$(shell date -Iminutes)"
frogtest-tptp:
	@echo "start benchmarks in ${BENCH_DIR}"
	mkdir -p ${BENCH_DIR}
	cp zipperposition.native hornet.native ${BENCH_DIR}/
	ln -s ../tptp/ ${BENCH_DIR}/tptp
	cp data/bench.toml ${BENCH_DIR}/conf.toml
	cd ${BENCH_DIR} && frogtest run --meta=`git rev-parse HEAD` \
	  -c conf.toml

TARBALL=zipperposition.tar.gz

package: clean
	rm $(TARBALL) || true
	oasis setup
	tar cavf $(TARBALL) _oasis setup.ml configure myocamlbuild.ml _tags \
		Makefile pelletier_problems README.md src/ tests/ utils/

WATCH?=all
watch:
	while find src/ tests/ -print0 | xargs -0 inotifywait -e delete_self -e modify ; do \
		echo "============ at `date` ==========" ; \
		make $(WATCH); \
	done

ocp-indent:
	@which ocp-indent > /dev/null || { \
	  	echo 'ocp-indent not found; please run `opam install ocp-indent`'; \
		exit 1 ; \
	  }

reindent: ocp-indent
	@find src '(' -name '*.ml' -or -name '*.mli' ')' -print0 | xargs -0 echo "reindenting: "
	@find src '(' -name '*.ml' -or -name '*.mli' ')' -print0 | xargs -0 ocp-indent -i

gallery.svg:
	for i in gallery/*.dot ; do dot -Tsvg "$$i" > "gallery/`basename $${i} .dot`.svg" ; done

clean-generated:
	rm myocamlbuild.ml || true
	find \( -name '*.mldylib' -or -name '*.mlpack' \
	  -or -name '*.mllib' -or -name '*.odocl' \) -delete

.PHONY: push_doc dot package tags rst_doc open_doc test-all clean-generated

