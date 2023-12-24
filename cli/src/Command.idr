module Command

import Collie
import Collie.Options.Domain
import Data.List1

import Data.Version

%hide Data.Record.SmartConstructors.Infer.infix.(::=)
%hide Collie.Modifiers.infix.(::=)

orError : (err : String) -> Maybe a -> Either String a
orError err = maybe (Left err) Right

public export
version : Arguments
version = MkArguments True (Some Version) (orError "Expected a semantic version argument." . parseVersion)

public export
idv : Command "idv"
idv = MkCommand
  { description = """
                  An Idris 2 version manager. Facilitates simultaneous installation of multiple \
                  Idris 2 versions.
                  """
  , subcommands =
     [ "--help"    ::= basic "Print this help text." none
     , "list"      ::= basic "List all installed and available Idris 2 versions." none
     , "install"   ::= installCommand
     , "uninstall" ::= uninstallCommand
     , "select"    ::= selectCommand
     ]
  , modifiers = []
  , arguments = none
  }
  where
    installCommand : Command "install"
    installCommand = MkCommand
      { name = "install"
      , description = """
                      <version> Install the given Idris 2 version and optionally also install the Idris 2 API.
                      Although you can switch to the system or pack installs, you cannot install those special \
                      targets via this command.
                      """
      , subcommands = []
      , modifiers = [
            "--api" ::= (flag $ """
                                Install the Idris 2 API package after installing Idris 2.
                                If the specified version of Idris 2 is already installed, \
                                the API package will be added under the specified installation.
                                """)
          , "--lsp" ::= (flag $ """
                                Install the Idris 2 LSP after installing Idris 2.
                                If the specified version of Idris 2 is already installed, \
                                the LSP server will be added under the specified installation.
                                """)
          ]
      , arguments = version
      }

    uninstallCommand : Command "uninstall"
    uninstallCommand = MkCommand
      { name = "uninstall"
      , description = """
                      <version> Uninstall the given Idris 2 version.
                      Although you can switch to the system or pack installs, you cannot uninstall those special \
                      targets via this command.
                      """
      , subcommands = []
      , modifiers = []
      , arguments = version
      }

    selectCommand : Command "select"
    selectCommand = MkCommand
      { name = "select"
      , description = "<version> Select the given (already installed) version of Idris 2."
      , subcommands = 
        [ "system" ::= basic "Select the system install of Idris 2 (generally ~/.idris2/bin/idris2)." none
        , "pack"   ::= basic "Select the pack install of Idris 2 (generally ~/.pack/bin/idris2)." none
        ]
      , modifiers = []
      , arguments = version
      }

public export
(.handleWith) : {nm : String} -> (cmd : Command nm) -> (cmd ~~> IO a) -> IO a
cmd .handleWith h
  = do Right args <- cmd.parseArgs
         | Left err => do putStrLn err
                          putStrLn ""
                          putStrLn (cmd .usage)
                          putStrLn ""
                          exitFailure
       let Pure args = finalising args
         | Fail err => do putStrLn (show err)
                          exitFailure
       handle args h

