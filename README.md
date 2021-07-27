
# Idv

**Idv** is a simple CLI for installing different versions of Idris 2 on a computer at the same time. It also makes switching between those versions effortless.

_Why the name Idv?_ Idv is short for IDris Version manager and it's executable (`idv`) importantly shares very few characters in common with `idris2` (the name of the Idris 2 compiler & REPL executable). The latter point means that `idv` does not hurt your tab completion too much because you can still tab complete to `idris2 after the first three characters.

## How it works

Idv will check out a copy of the Idris 2 source code and use it to bootstrap & build any of the available Idris 2 versions. It then installs those versions in a directory it owns so that it can symlink to different versions of the Idris 2 executable to allow fast switching between installed versions.

## Prerequisites

Because Idv will build Idris 2 from source, it has the same system requirements as building Idris 2 the requested version would have. To make things simple, you can use the following list for any Idris 2 version as of this writing:
- Chez Scheme
- bash
- GNU make
- sha256sum
- GMP

_Ironically_, Idv is not currently available as a prebuilt binary, which means you will need to have Idris 2 installed on your system in order to build & install Idv.

Snag a copy of Idris 2 (or build it from source) and install it as normal. Idv will let you switch to your system copy in addition to versions installed by Idv, so it is not a total loss to have Idris 2 installed outside of Idv.

NOTE: For now, Idv will always assume the system Idris 2 install is located at the default path of `~/.idris2/bin`.

## Installation

Download the source and then build and install Idv.
```shell
make && make install
```

Idv installs into `~/.idv` by default. You can optionally specify a non-default install location with the INSTALLDIR environment variable -- be sure to specify this variable for both the `make` and `make install` commands:
```shell
INSTALLDIR=~/staging/idrv make && make install
```

Add the `bin` directory inside the chosen install location (by default, `~/.idv/bin`) to your PATH environment variable somewhere _before_ the system install of Idris 2 (`~/.idris2/bin`). This is important to allow Idv to switch between shadowing or exposing the system installed version.

## Usage

```shell
Usage: idv <subcommand>
  Subcommands:
   - list                 list all installed and available Idris 2 versions.
   - install <version>    install the given Idris 2 version.
   - select <version>     select the given (already installed) Idris 2 version.
   - select system        select the system Idris 2 install (generally ~/.idris2/bin/idris2).
```

For example, if you have run `idv install 0.3.0` then you can switch back and forth between the official 0.4.0 version and a version of Idris 2 you've installed from source with the HEAD of the main branch checked out as follows:
```shell
$ idv select 0.3.0

Idris 2 version 0.3.0 selected.

$ idris2 --version
Idris 2, version 0.3.0
$ idv select system

System copy of Idris 2 selected.

$ idris2 --version
Idris 2, version 0.4.0-b03395deb
```

