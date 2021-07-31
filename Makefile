
INSTALLDIR ?= ~/.idv
IDRIS2 ?= ~/.idris2/bin/idris2

EXECDIR = $(INSTALLDIR)/bin
IDRISVERSIONDIR = $(INSTALLDIR)/versions
CHECKOUTDIR = $(INSTALLDIR)/checkout

all: build

.PHONY: build install clean

build:
	@INSTALLDIR="$(INSTALLDIR)" IDRIS2="$(IDRIS2)" ./generate_paths.sh
	idris2 --build idv.ipkg

install:
	@mkdir -p $(EXECDIR) && \
	mkdir -p $(IDRISVERSIONDIR) && \
	mkdir -p $(CHECKOUTDIR) && \
	cp -R ./build/exec/* $(EXECDIR) && \
	echo "\nIdv installed to $(INSTALLDIR).\nThis is not automatically in your PATH.\nAdd $(EXECDIR) to your PATH to complete installation.\n"
	@echo "\nTIP: Add Idv to your path before Idris's install location\nso that Idv can non-destructively point your shell at\ndifferent Idris versions.\n"

clean:
	rm -rf ./build
