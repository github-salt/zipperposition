# OASIS_START
# DO NOT EDIT (digest: 9a60866e2fa295c5e33a3fe33b8f3a32)

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

setup.exe: setup.ml
	ocamlfind ocamlopt -o $@ -linkpkg -package oasis.dynrun $< || ocamlfind ocamlc -o $@ -linkpkg -package oasis.dynrun $< || true
	$(RM) setup.cmi setup.cmo setup.cmx setup.o

.PHONY: build doc test all install uninstall reinstall clean distclean configure

# OASIS_STOP

rst_doc:
	@echo "build Sphinx documentation (into _build/doc)"
	sphinx-build doc _build/doc

open_doc: rst_doc
	firefox _build/doc/contents.html

push_doc: doc rst_doc
	rsync -tavu logtk.docdir/* cedeela.fr:~/simon/root/software/logtk/
	rsync -tavu _build/doc/* cedeela.fr:~/simon/root/software/logtk/rst/

test-all: build
	./run_tests.native
	./tests/quick/all.sh

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

frogtest-tip:
	@[ -d tip-benchmarks ] || (echo "missing tip-benchmarks/" && exit 1)
	frogtest run --meta=`git rev-parse HEAD` \
	  -c ./tip-benchmarks/conf.toml \
	  tip-benchmarks/

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

gallery.svg:
	for i in gallery/*.dot ; do dot -Tsvg "$$i" > "gallery/`basename $${i} .dot`.svg" ; done

clean-generated:
	rm myocamlbuild.ml || true
	find \( -name '*.mldylib' -or -name '*.mlpack' \
	  -or -name '*.mllib' -or -name '*.odocl' \) -delete

.PHONY: push_doc dot package tags rst_doc open_doc test-all clean-generated

