module Main

import Data.List
import Data.Maybe
import Data.Either
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

||| The install location of the system copy of Idris 2.
||| If Idris 2 cannot be located on the system (i.e.
||| outside of the Idv versions directory) this function
||| returns Nothing.
systemIdrisPath : HasIO io => io (Maybe String)
systemIdrisPath = do
  Nothing <- checkLocation =<< getEnv "IDRIS2"
    | Just envOverride => pure $ Just envOverride
  checkLocation =<< defaultPath
    where
      defaultPath : io (Maybe String)
      defaultPath = pathExpansion $ defaultIdris2Location

      checkLocation : Maybe String -> io (Maybe String)
      checkLocation Nothing     = pure Nothing
      checkLocation (Just path) = pure $ if !(exists path) then Just path else Nothing

createVersionsDir : HasIO io => Version -> io ()
createVersionsDir version = do
  Just resolvedVersionsDir <- pathExpansion $ versionPath version
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

||| Check out the given version if available (in the checkout folder
||| in preparation for building against a particular version of the
||| Idris 2 source code).
checkoutIfAvailable : HasIO io => Version -> io (Either String ())
checkoutIfAvailable version = do
  fromMaybe (Left "Failed to switch to checkout directory.") <$>
    changeDirAndCheckout
      where
        changeDirAndCheckout : io (Maybe (Either String ()))
        changeDirAndCheckout =
          inDir relativeCheckoutPath $ do
            updateMainBranch
            availableVersions <- listVersions
            case find (== version) availableVersions of
                 Nothing => pure $ Left "Version \{show version} is not one of the available versions: \{show availableVersions}."
                 (Just resolvedVersion) => do 
                   True <- checkout resolvedVersion.tag
                     | False => pure $ Left "Could not check out requested version of Idris2."
                   pure $ Right ()

||| Assumes the current working directory is an Idris repository.
bootstrapBuild : HasIO io => (resolvedVersion : Version) -> (buildPrefix : String) -> io ()
bootstrapBuild version buildPrefix = do
  True <- go
    | False => exitError "Failed to build Idris2 version \{show version}."
  pure ()
    where
      chezExec : io (Maybe String)
      chezExec = pure $ if !(eatOutput True "which chez") then Just "chez" else Nothing

      schemeExec : io (Maybe String)
      schemeExec = pure $ if !(eatOutput True "which scheme") then Just "scheme" else Nothing

      envExec : io (Maybe String)
      envExec = getEnv "SCHEME"


      go : io Bool
      go = do
        Just exec <- pure $ !chezExec <|> !schemeExec <|> !envExec
          | Nothing => do
              putStrLn "Could not find Scheme executable. Specify executable to use with SCHEME environment variable."
              pure False
        putStrLn "Building with Scheme executable: \{exec}"
        res <- system "make clean && PREFIX=\"\{buildPrefix}\" SCHEME=\"\{exec}\" make bootstrap"
        pure $ res == 0

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

buildAndInstall : HasIO io => Version -> (cleanAfter : Bool) -> io ()
buildAndInstall version cleanAfter = do
  Right _ <- checkoutIfAvailable version
    | Left err => exitError err
  moveDirRes <- inDir relativeCheckoutPath $ do
    let proposedInstalledDir = installedIdrisPath version
    let proposedBuildPrefix = buildPrefix version
    Just installedDir <- pathExpansion proposedInstalledDir
      | Nothing => exitError "Could not resolve install directory: \{proposedInstalledDir}."
    Just buildPrefix <- pathExpansion proposedBuildPrefix
      | Nothing => exitError "Could not resolve build prefix directory: \{proposedBuildPrefix}."
    -- bootstrap build
    bootstrapBuild version buildPrefix
    install False installedDir version buildPrefix
    -- non-bootstrap build
    cleanAndBuild version installedDir buildPrefix
    install True installedDir version buildPrefix
    when cleanAfter $
      -- clean up
      ignore $ clean
  unless (isJust moveDirRes) $ 
    exitError "Failed to install version \{show version}."

installApi : HasIO io => io ()
installApi = do
  0 <- system "make install-api"
    | _ => exitError "Failed to install Idris2 API package."
  putStrLn ""
  putStrLn "Idris2 API package successfully installed."
  ignore $ clean

unselect : HasIO io => io ()
unselect = do
  Just lnFile <- pathExpansion $ idrisSymlinkedPath
    | Nothing => exitError "Could not resolve Idris 2 symlink path."
  Right () <- removeFile lnFile
    | Left FileNotFound => pure () -- no problem here, job done.
    | Left err => exitError "Failed to remove symlink file (to let system Idris 2 installation take precedence): \{show err}."
  pure ()

||| Attempt to select the given version. Fails if the version
||| requested is not installed.
selectVersion : HasIO io => Version -> io (Either String ())
selectVersion proposedVersion = do
  Just localVersions <- Local.listVersions
    | Nothing => pure $ Left "Could not look up local versions."
  case find (== proposedVersion) localVersions of
       Nothing      => pure $ Left "Idris 2 version \{show proposedVersion} is not installed.\nInstalled versions: \{show localVersions}."
       Just version => do
         unselect
         let proposedInstalled = installedIdrisPath version
         let proposedSymlinked = idrisSymlinkedPath
         Just installed <- pathExpansion proposedInstalled
           | Nothing => pure $ Left "Could not resolve install location: \{proposedInstalled}."
         Just linked <- pathExpansion proposedSymlinked
           | Nothing => pure $ Left "Could not resolve symlinked location: \{proposedSymlinked}."
         True <- symlink installed linked
           | False => pure $ Left "Failed to create symlink for Idris 2 version \{show version}."
         pure $ Right ()

||| Select the given version if it is installed (as in set it as the version used
||| when the `idris2` command is executed). Then checkout that same version in the
||| checkout folder where builds are performed.
selectAndCheckout : HasIO io => (versionStr : String) -> io Bool
selectAndCheckout version =
  case parseVersion version of
       Nothing => pure False
       Just parsedVersion => do
         Right _ <- selectVersion parsedVersion
           | Left _  => pure False
         Right _ <- checkoutIfAvailable parsedVersion
           | Left _ => pure False
         pure True
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
  systemInstall <- systemIdrisPath
  when (isJust systemInstall) $
    putStrLn "system (installed)"
  traverse_ putStrLn $ printVersion <$> zipMatch localVersions remoteVersions
    where
      printVersion : (Maybe Version, Maybe Version) -> String
      printVersion (Just v, Just _)  = "\{show v}  (installed)"
      printVersion (Nothing, Just v) = show v
      printVersion (Just v, Nothing) = "\{show v}  (local only)"
      printVersion (Nothing, Nothing) = ""

installCommand : HasIO io => (versionStr : String) -> (cleanAfter : Bool) -> io ()
installCommand versionStr cleanAfter =
  case parseVersion versionStr of
       Nothing      => exitError "Could not parse \{versionStr} as a version."
       Just version => do
         createVersionsDir version
         buildAndInstall version cleanAfter

selectCommand : HasIO io => (versionStr : String) -> io ()
selectCommand versionStr = do
  let parsedVersion = parseVersion versionStr
  case parsedVersion of
       Nothing      => exitError "Could not parse \{versionStr} as a version."
       Just version => do
         Right () <- selectVersion version
           | Left err => exitError err
         pure ()

selectSystemCommand : HasIO io => io ()
selectSystemCommand = do
  unselect
  let proposedSymlinked = idrisSymlinkedPath
  Just installed <- systemIdrisPath
    | Nothing => exitError "Could not find system install of Idris 2. You might have to run this command with the IDRIS2 environment variable set to the location of the idris2 binary because it is not located at \{defaultIdris2Location}."
  Just linked <- pathExpansion proposedSymlinked
    | Nothing => exitError "Could not resolve symlinked location: \{proposedSymlinked}."
  True <- symlink installed linked
    | False => exitError "Failed to create symlink for Idris 2 system install."
  pure ()

-- TODO: integrate https://github.com/ohad/collie instead of the following thrown together stuff
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
  installCommand version True
  pure True
handleSubcommand ["install", version, "--api"] = do
  -- we won't reinstall if not needed:
  unless !(selectAndCheckout version) $ do
    installCommand version False
    selectCommand version
  ignore $ inDir relativeCheckoutPath installApi
  pure True

handleSubcommand ("install" :: more) = do
  if length more == 0
     then putStrLn "Install command expects a <version> argument."
     else putStrLn "Bad arguments to install command: \{unwords more}."
  pure True
handleSubcommand ["select", "system"] = do
  selectSystemCommand
  exitSuccess "System copy of Idris 2 selected."
handleSubcommand ["select", version] = do
  selectCommand version
  exitSuccess "Idris 2 version \{show version} selected."
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
  putStrLn """ 
  \nUsage: idv <subcommand>

    Subcommands:
     - list                 list all installed and available Idris 2 versions.
     - install <version>    install the given Idris 2 version.
     - select <version>     select the given (already installed) Idris 2 version.
     - select system        select the system Idris 2 install (generally ~/.idris2/bin/idris2).
  """
  pure ()

main : IO ()
main = do
  Just _ <- inDir idvLocation run
    | Nothing => exitError "Could not access \{idvLocation}."
  pure ()

