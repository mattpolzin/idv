module Main

import Data.List
import Data.Version
import Data.String
import Data.Maybe
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

listVersions : HasIO io => io ()
listVersions = do
  True <- cloneIfNeeded idrisRepoURL relativeCheckoutPath
    | False => exitError "Failed to clone Idris repository into local folder."
  Just versions <- inDir relativeCheckoutPath fetchAndListVersions
    | Nothing => exitError "Failed to retrieve versions."
  printLn versions

bootstrapBuild : HasIO io => io Bool
bootstrapBuild = [ res == 0 | res <- system "make clean && SCHEME=chez make bootstrap" ]
  -- TODO: ^ support other possible Chez Scheme incantations.
  --       use which to locate either 'scheme' or 'chez'?
  --       fall back to ENV variable for SCHEME?

installVersion : HasIO io => (versionStr : String) -> io ()
installVersion versionStr = do
  case parseVersion versionStr of
       Nothing      => exitError "Could not parse \{versionStr} as a version."
       Just version => do
         res <- inDir relativeCheckoutPath $ do
           True <- checkoutAndPullBranch "main"
             | False => exitError "Could not update idris repository prior to building a new version."
           True <- checkout version.tag
             | False => exitError "Could not check out requested version of Idris."
           True <- bootstrapBuild
             | False => exitError "Failed to build Idris version \{versionStr}."
           -- TODO: install to versions directory
           -- TODO: select this version (symlink into execLocation)
           pure ()
         unless (isJust res) $ 
           exitError "Failed to install version \{versionStr}."

||| Handle a subcommand and return True if the input has
||| been handled or False if no action has been taken based
||| on the input.
handleSubcommand : HasIO io => List String -> io Bool
handleSubcommand ["list"] = do
  listVersions
  pure True
handleSubcommand ("list" :: more) = do
  putStrLn "Unknown arguments to list command: \{unwords more}."
  listVersions
  pure True
handleSubcommand ["install", version] = do
  installVersion version
  pure True
handleSubcommand ("install" :: more) = do
  if length more == 0
     then putStrLn "Install command expects <version> argument."
     else putStrLn "Bad arguments to install command: \{unwords more}."
  pure True
handleSubcommand _ = pure False

run : IO ()
run = do
  args <- drop 1 <$> getArgs
  False <- handleSubcommand args
    | True => pure ()
  if length args /= 0
     then putStrLn "Unknown subcommand: \{unwords args}"
     else putStrLn "Expected a subcommand."
  -- TODO: print usage.
  pure ()

main : IO ()
main = do
  Just _ <- inDir execLocation run
    | Nothing => exitError "Could not access \{execLocation}."
  pure ()

