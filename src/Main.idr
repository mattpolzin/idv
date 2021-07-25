module Main

import Data.List
import Data.Version
import System
import System.Console.GetOpt

import Git

exitError : HasIO io => String -> io a
exitError err = do
  putStrLn ""
  putStrLn err
  putStrLn ""
  exitFailure

idrisRepoURL : String
idrisRepoURL = "https://github.com/idris-lang/Idris2.git"

relativeCheckoutPath : String
relativeCheckoutPath = "./checkout"

handleSubcommand : HasIO io => List String -> io Bool
handleSubcommand ("list" :: xs) = do
  True <- cloneIfNeeded idrisRepoURL relativeCheckoutPath
    | False => exitError "Failed to clone Idris repository into local folder."
  ignore $ fetch relativeCheckoutPath
  versions <- listVersions relativeCheckoutPath
  printLn versions
  pure True
handleSubcommand _ = pure False

main : IO ()
main = do
  args <- drop 1 <$> getArgs
  False <- handleSubcommand args
    | True => pure ()
  pure ()
