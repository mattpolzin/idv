module Main

import Git
import System
import System.Console.GetOpt
import Data.List

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
  pure True
handleSubcommand _ = pure False

main : IO ()
main = do
  args <- drop 1 <$> getArgs
  False <- handleSubcommand args
    | True => putStrLn "Done 1"
  putStrLn "Done 2"
