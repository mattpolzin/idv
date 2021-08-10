
CWD = $(shell pwd)

INSTALLDIR ?= ~/.idv
IDRIS2 ?= ~/.idris2/bin/idris2

EXECDIR = $(INSTALLDIR)/bin
IDRISVERSIONDIR = $(INSTALLDIR)/versions
CHECKOUTDIR = $(INSTALLDIR)/checkout

INTERACTIVE_TESTS ?= --interactive
TEST_INSTALLDIR ?= $(CWD)/tests/.idv

all: build

.PHONY: build install test clean deps build-idv build-backend

depends/collie-0:
	@mkdir -p depends/collie-0 && \
	mkdir -p deps-build && \
	cd deps-build && \
	rm -rf ./collie && \
	git clone https://github.com/ohad/collie.git && \
	cd collie && \
	git checkout 31b2fec && \
	make && \
	cp -R ./build/ttc/* ../../depends/collie-0 && \
	cd ../.. && \
	rm -rf ./deps-build/collie

depends/idv-backend-0: backend/src
	@mkdir -p depends/idv-backend-0 && \
	rm -rf ./build && \
	INSTALLDIR="$(INSTALLDIR)" IDRIS2="$(IDRIS2)" ./generate_paths.sh
	cd backend && \
	idris2 --build idv-backend.ipkg &&\
	cp -R ./build/ttc/* ../depends/idv-backend-0 && \
	rm -rf ./build

deps: depends/collie-0 depends/idv-backend-0

build-idv: 
	idris2 --build idv.ipkg

build-backend: depends/idv-backend-0

build: deps build-idv

install:
	@mkdir -p $(EXECDIR) && \
	mkdir -p $(IDRISVERSIONDIR) && \
	mkdir -p $(CHECKOUTDIR) && \
	cp -R ./build/exec/* $(EXECDIR) && \
	echo "\nIdv installed to $(INSTALLDIR).\nThis is not automatically in your PATH.\nAdd $(EXECDIR) to your PATH to complete installation.\n"
	@echo "\nTIP: Add Idv to your path before Idris's install location\nso that Idv can non-destructively point your shell at\ndifferent Idris versions.\n"

clean-tests:
	rm -rf ./tests/build
	rm -rf ./tests/.idv/bin
	rm -rf ./tests/.idv/checkout

clean-backend:
	rm -rf ./depends/idv-backend-0

clean: clean-tests clean-backend
	rm -rf ./depends
	rm -rf ./build
	rm -rf ./backend/build

tests/.idv/bin/idv:
	INSTALLDIR=$(TEST_INSTALLDIR) make
	INSTALLDIR=$(TEST_INSTALLDIR) make install

tests/.idv/versions/0_2_1:
	$(TEST_INSTALLDIR)/bin/idv install 0.2.1

test: clean tests/.idv/bin/idv tests/.idv/versions/0_2_1
	cd tests && \
	idris2 --build tests.ipkg && \
	./build/exec/test_idv $(TEST_INSTALLDIR)/bin/idv $(INTERACTIVE_TESTS)

