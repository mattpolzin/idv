module Main

import Data.List
import Data.Maybe
import Data.String
import Data.Version
import System
import System.Console.Extra
import System.Directory.Extra
import System.File
import System.File.Extra
import System.Path

import Git
import Local
import IdvPaths

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

||| Get the name of the directory where the given version is installed
||| This is the directory relative to `idvLocation`/`relativeVersionsPath`
versionDir : Version -> String
versionDir (V major minor patch _) = "\{show major}_\{show minor}_\{show patch}"

buildPrefix : Version -> String
buildPrefix version = 
  idvLocation </> relativeVersionsPath </> (versionDir version)

systemIdrisPath : String
systemIdrisPath = 
  "~" </> ".idris2" </> "bin" </> "idris2"

installedIdrisPath : Version -> String
installedIdrisPath version = 
  idvLocation </> relativeVersionsPath </> (versionDir version) </> "bin" </> "idris2"

idrisSymlinkedPath : String
idrisSymlinkedPath = 
  idvLocation </> relativeBinPath </> "idris2"

createVersionsDir : HasIO io => Version -> io ()
createVersionsDir version = do
  Just resolvedVersionsDir <- pathExpansion $ idvLocation </> relativeVersionsPath </> (versionDir version)
    | Nothing => exitError "Could not resolve install directory for new Idris2 version."
  True <- createDirIfNeeded $ resolvedVersionsDir
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
  Just remoteVersions <- inDir relativeCheckoutPath fetchAndListVersions
    | Nothing => exitError "Failed to retrieve remote versions."
  Just localVersions <- Local.listVersions
    | Nothing => exitError "Failed to list local versions."
  traverse_ putStrLn $ printVersion <$> zipMatch localVersions remoteVersions
    where
      printVersion : (Maybe Version, Maybe Version) -> String
      printVersion (Just v, Just _)  = "\{show v} (installed)"
      printVersion (Nothing, Just v) = show v
      printVersion (Just v, Nothing) = "\{show v} (missing)"
      printVersion (Nothing, Nothing) = ""

installCommand : HasIO io => (versionStr : String) -> io ()
installCommand versionStr =
  case parseVersion versionStr of
       Nothing      => exitError "Could not parse \{versionStr} as a version."
       Just version => do
         createVersionsDir version
         buildAndInstall version

unselect : HasIO io => io ()
unselect = do
  Just lnFile <- pathExpansion $ idrisSymlinkedPath
    | Nothing => exitError "Could not resolve Idris 2 symlink path."
  Right () <- removeFile lnFile
    | Left FileNotFound => pure () -- no problem here, job done.
    | Left err => exitError "Failed to remove symlink file (to let system Idris 2 installation take precedence): \{show err}."
  pure ()

selectCommand : HasIO io => (versionStr : String) -> io ()
selectCommand versionStr = do
  Just localVersions <- Local.listVersions
    | Nothing => exitError "Could not look up local versions."
  let parsedVersion = parseVersion versionStr
  let condition = (==) <$> parsedVersion
  case (flip find localVersions) =<< condition of
       Nothing      => if isNothing parsedVersion 
                          then exitError "Could not parse \{versionStr} as a version."
                          else exitError "Idris 2 version \{versionStr} is not installed.\nInstalled versions: \{show localVersions}."
       Just version => do
         unselect
         let proposedInstalled = installedIdrisPath version
         let proposedSymlinked = idrisSymlinkedPath
         Just installed <- pathExpansion proposedInstalled
           | Nothing => exitError "Could not resolve install location: \{proposedInstalled}."
         Just linked <- pathExpansion proposedSymlinked
           | Nothing => exitError "Could not resolve symlinked location: \{proposedSymlinked}."
         True <- symlink installed linked
           | False => exitError "Failed to create symlink for Idris 2 version \{show version}."
         exitSuccess "Idris 2 version \{show version} selected."

selectSystemCommand : HasIO io => io ()
selectSystemCommand = do
  unselect
  let proposedInstalled = systemIdrisPath
  let proposedSymlinked = idrisSymlinkedPath
  Just installed <- pathExpansion proposedInstalled
    | Nothing => exitError "Could not resolve install location: \{proposedInstalled}."
  Just linked <- pathExpansion proposedSymlinked
    | Nothing => exitError "Could not resolve symlinked location: \{proposedSymlinked}."
  True <- symlink installed linked
    | False => exitError "Failed to create symlink for Idris 2 system install."
  exitSuccess "System copy of Idris 2 selected."

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
     then putStrLn "Install command expects a <version> argument."
     else putStrLn "Bad arguments to install command: \{unwords more}."
  pure True
handleSubcommand ["select", "system"] = do
  selectSystemCommand
  pure True
handleSubcommand ["select", version] = do
  selectCommand version
  pure True
handleSubcommand ("select" :: more) = do
  if length more == 0
     then putStrLn "Select command expects a <version> argument."
     else putStrLn "Bad arguments to select command: \{unwords more}."
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
  Just _ <- inDir idvLocation run
    | Nothing => exitError "Could not access \{idvLocation}."
  pure ()

