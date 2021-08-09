module Main

import Collie

import Interface
import Data.Version
import System.Directory.Extra
import Command

%hide Collie.(.handleWith)

exitError : HasIO io => String -> io a
exitError err = do
  putStrLn ""
  putStrLn err
  putStrLn ""
  exitFailure

exitSuccess : HasIO io => String -> io a
exitSuccess msg = do
  putStrLn ""
  putStrLn msg
  putStrLn ""
  exitSuccess

--
-- Entrypoint
--

-- Handling more complex commands (with arguemnts and modifiers) first
-- makes compile times shorter.
handleCommand' : Command.idv ~~> IO ()
handleCommand' =
  [ const $ do putStrLn "Expected a subcommand."
               exitError idv.usage
  , "install" ::= [ (\args => let version = args.arguments
                              in  if args.modifiers.project "--api"
                                     then installAPICommand version
                                     else installCommand version True
                    ) ]
  , "select"  ::= [ (\args => let version = args.arguments
                              in  selectCommand version )
                  , "system" ::= [ const selectSystemCommand ]
                  ]
  , "--help"  ::= [ const . exitSuccess $ idv.usage ]
  , "list"    ::= [ const listVersionsCommand ]
  ]


main : IO ()
main = do
  Just _ <- inDir idvLocation $ idv.handleWith handleCommand'
    | Nothing => exitError "Could not access \{idvLocation}."
  pure ()

