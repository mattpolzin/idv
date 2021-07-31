
INSTALLDIR ?= ~/.idv
IDRIS2 ?= ~/.idris2/bin/idris2

EXECDIR = $(INSTALLDIR)/bin
IDRISVERSIONDIR = $(INSTALLDIR)/versions
CHECKOUTDIR = $(INSTALLDIR)/checkout

all: build

.PHONY: build install clean deps build-idv

depends/collie-0:
	@mkdir -p depends/collie-0 && \
	mkdir -p deps-build && \
	cd deps-build && \
	rm -rf ./collie && \
	git clone https://github.com/ohad/collie.git && \
	cd collie && \
	make && \
	cp -R ./build/ttc/* ../../depends/collie-0 && \
	cd ../.. && \
	rm -rf ./deps-build/collie

deps: depends/collie-0

build-idv: 
	@INSTALLDIR="$(INSTALLDIR)" IDRIS2="$(IDRIS2)" ./generate_paths.sh
	idris2 --build idv.ipkg

build: deps build-idv

install:
	@mkdir -p $(EXECDIR) && \
	mkdir -p $(IDRISVERSIONDIR) && \
	mkdir -p $(CHECKOUTDIR) && \
	cp -R ./build/exec/* $(EXECDIR) && \
	echo "\nIdv installed to $(INSTALLDIR).\nThis is not automatically in your PATH.\nAdd $(EXECDIR) to your PATH to complete installation.\n"
	@echo "\nTIP: Add Idv to your path before Idris's install location\nso that Idv can non-destructively point your shell at\ndifferent Idris versions.\n"

clean:
	rm -rf ./depends
	rm -rf ./build
