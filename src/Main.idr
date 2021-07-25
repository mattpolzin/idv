module Main

import Data.List
import Data.Version
import Data.String
import System
import System.Directory.Extra
import System.Console.Extra
import System.Path

import Git

exitError : HasIO io => String -> io a
exitError err = do
  putStrLn ""
  putStrLn err
  putStrLn ""
  exitFailure

execLocation : HasIO io => io (Maybe String)
execLocation = (parent =<<) . head' <$> readLines (limit 1) False "which idrv"
--   where
--     dropLastPathComponent : String -> Maybe String
--     dropLastPathComponent = parent
-- 
--     nonEmpty : String -> Maybe String
--     nonEmpty "" = Nothing
--     nonEmpty str = Just str

idrisRepoURL : String
idrisRepoURL = "https://github.com/idris-lang/Idris2.git"

relativeCheckoutPath : String
relativeCheckoutPath = "../checkout"

relativeVersionsPath : String
relativeVersionsPath = "../versions"

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
  Just execLoc <- execLocation
    | Nothing => exitError "Could not find install location for idrv."
  Just _ <- inDir execLoc run
    | Nothing => exitError "Could not access \{execLoc}."
  pure ()

