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

||| Get the name of the directory where the given version is installed
||| This is the directory relative to `idrvLocation`/`relativeVersionsPath`
versionDir : Version -> String
versionDir (V major minor patch _) = "\{show major}_\{show minor}_\{show patch}"

buildPrefix : Version -> String
buildPrefix version = 
  idrvLocation </> relativeVersionsPath </> (versionDir version)

installedIdrisPath : Version -> String
installedIdrisPath version = 
  idrvLocation </> relativeVersionsPath </> (versionDir version) </> "bin" </> "idris2"

||| Assumes the current working directory is the `idrvLocation`.
createVersionsDir : HasIO io => Version -> io ()
createVersionsDir version = do
  True <- createDirIfNeeded $ relativeVersionsPath </> (versionDir version)
    | False => exitError "Could not create install directory for new Idris2 version."
  pure ()

||| Assumes the current working directory is an Idris repository.
updateMainBranch : HasIO io => io ()
updateMainBranch = do
  True <- checkoutAndPullBranch "main"
    | False => exitError "Could not update Idris2 repository prior to building a new version."
  pure ()

||| Assumes the current working directory is an Idris repository.
clean : HasIO io => io Bool
clean = [ res == 0 | res <- system "make clean" ]

||| Builds the current repository _using_ the executable for the
||| given version. This means you must have already installed the
||| given version into the versions folder (possibly as a bootstrap
||| build).
||| Assumes the current working directory is an Idris repository.
build : HasIO io => (idrisExecutable : Version) -> (installedDir : String) -> (buildPrefix : String) -> io Bool
build version installedDir buildPrefix = 
  [ res == 0 | res <- system "PREFIX=\"\{buildPrefix}\" IDRIS2_BOOT=\"\{installedDir}\" make" ]

||| Assumes the current working directory is an Idris repository.
cleanAndBuild : HasIO io => Version -> (installedDir : String) -> (buildPrefix : String) -> io ()
cleanAndBuild version installedDir buildPrefix = do
  True <- clean
    | False => exitError "Could not clean before building."
  True <- build version installedDir buildPrefix
    | False => exitError "Failed to build the current repository with the Idris executable that should have been installed into \{installedIdrisPath version}."
  pure ()

||| Assumes the current working directory is an Idris repository.
checkoutAndBuild : HasIO io => (resolvedVersion : Version) -> (buildPrefix : String) -> io ()
checkoutAndBuild version buildPrefix = do
  True <- checkout version.tag
    | False => exitError "Could not check out requested version of Idris2."
  True <- bootstrapBuild
    | False => exitError "Failed to build Idris2 version \{show version}."
  pure ()
    where
      bootstrapBuild : io Bool
      bootstrapBuild = 
        [ res == 0 | res <- system "make clean && PREFIX=\"\{buildPrefix}\" SCHEME=chez make bootstrap" ]
        -- TODO: ^ support other possible Chez Scheme incantations.
        --       use which to locate either 'scheme' or 'chez'?
        --       fall back to ENV variable for SCHEME?

||| Assumes the current working directory is an Idris repository.
||| If `installOver` is True, the Idris 2 executable in the versions
||| directory for the version specified will be used (it will be asked
||| for the --libdir which affects where Idris installs the std libraries
||| included).
install : HasIO io => (installOver : Bool) -> (installedDir : String) -> Version -> (buildPrefix : String) -> io ()
install installOver installedDir version buildPrefix = do
  let executableOverride = if installOver
                              then "IDRIS2_BOOT=\"\{installedDir}\""
                              else ""
  0 <- system "PREFIX=\"\{buildPrefix}\" \{executableOverride} make install"
    | _ => exitError "Failed to install Idris2 \{show version}."
  putStrLn ""
  putStrLn "Idris2 version \{show version} successfully installed to \{buildPrefix}."
  pure ()

buildAndInstall : HasIO io => Version -> io ()
buildAndInstall version = do
  moveDirRes <- inDir relativeCheckoutPath $ do
    updateMainBranch
    availableVersions <- listVersions
    case find (== version) availableVersions of
         Nothing => exitError "Version \{show version} is not one of the available versions: \{show availableVersions}."
         (Just resolvedVersion) => do 
           let proposedInstalledDir = installedIdrisPath resolvedVersion
           let proposedBuildPrefix = buildPrefix resolvedVersion
           Just installedDir <- pathExpansion proposedInstalledDir
             | Nothing => exitError "Could not resolve install directory: \{proposedInstalledDir}."
           Just buildPrefix <- pathExpansion proposedBuildPrefix
             | Nothing => exitError "Could not resolve build prefix directory: \{proposedBuildPrefix}."
           -- bootstrap build
           checkoutAndBuild resolvedVersion buildPrefix
           install False installedDir resolvedVersion buildPrefix
           -- non-bootstrap build
           cleanAndBuild resolvedVersion installedDir buildPrefix
           install True installedDir resolvedVersion buildPrefix
           -- clean up
           ignore $ clean
  unless (isJust moveDirRes) $ 
    exitError "Failed to install version \{show version}."

--
-- Commands
--

listVersionsCommand : HasIO io => io ()
listVersionsCommand = do
  True <- cloneIfNeeded idrisRepoURL relativeCheckoutPath
    | False => exitError "Failed to clone Idris2 repository into local folder."
  Just versions <- inDir relativeCheckoutPath fetchAndListVersions
    | Nothing => exitError "Failed to retrieve versions."
  printLn versions

installCommand : HasIO io => (versionStr : String) -> io ()
installCommand versionStr = do
  case parseVersion versionStr of
       Nothing      => exitError "Could not parse \{versionStr} as a version."
       Just version => do
         createVersionsDir version
         buildAndInstall version

||| Handle a subcommand and return True if the input has
||| been handled or False if no action has been taken based
||| on the input.
handleSubcommand : HasIO io => List String -> io Bool
handleSubcommand ["list"] = do
  listVersionsCommand
  pure True
handleSubcommand ("list" :: more) = do
  putStrLn "Unknown arguments to list command: \{unwords more}."
  listVersionsCommand
  pure True
handleSubcommand ["install", version] = do
  installCommand version
  pure True
handleSubcommand ("install" :: more) = do
  if length more == 0
     then putStrLn "Install command expects <version> argument."
     else putStrLn "Bad arguments to install command: \{unwords more}."
  pure True
handleSubcommand _ = pure False

--
-- Entrypoint
--

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
  Just _ <- inDir idrvLocation run
    | Nothing => exitError "Could not access \{idrvLocation}."
  pure ()

