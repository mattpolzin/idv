
all: build

.PHONY: build install clean

build:
	idris2 --build idrv.ipkg

install:
	idris2 --install idrv.ipkg

clean:
	rm -rf ./build
