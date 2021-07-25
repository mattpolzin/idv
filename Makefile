
INSTALLDIR ?= ~/.idrv

EXECDIR = $(INSTALLDIR)/bin
IDRISVERSIONDIR = $(INSTALLDIR)/versions

all: build

.PHONY: build install clean

build:
	@EXECDIR="$(EXECDIR)" ./generate_paths.sh
	idris2 --build idrv.ipkg

install:
	@mkdir -p $(EXECDIR) && \
	cp -R ./build/exec/* $(EXECDIR) && \
	echo "\nIdrv installed to $(INSTALLDIR).\nThis is not automatically in your PATH.\nAdd $(EXECDIR) to your PATH to complete installation.\n"
	@echo "\nTIP: Add Idrv to your path before Idris's install location\nso that Idrv can non-destructively point your shell at\ndifferent Idris versions.\n"

clean:
	rm -rf ./build
