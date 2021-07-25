module Main

import Data.List
import Data.Version
import Data.String
import System
import System.Directory.Extra
import System.Console.Extra
import System.Path

import IdrvPaths
import Git

exitError : HasIO io => String -> io a
exitError err = do
  putStrLn ""
  putStrLn err
  putStrLn ""
  exitFailure

handleSubcommand : HasIO io => List String -> io Bool
handleSubcommand ("list" :: xs) = do
  True <- cloneIfNeeded idrisRepoURL relativeCheckoutPath
    | False => exitError "Failed to clone Idris repository into local folder."
  ignore $ fetch relativeCheckoutPath
  versions <- listVersions relativeCheckoutPath
  printLn versions
  pure True
handleSubcommand _ = pure False

run : IO ()
run = do
  args <- drop 1 <$> getArgs
  False <- handleSubcommand args
    | True => pure ()
  pure ()

main : IO ()
main = do
  Just _ <- inDir execLocation run
    | Nothing => exitError "Could not access \{execLocation}."
  pure ()

