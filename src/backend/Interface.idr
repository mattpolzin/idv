module Interface

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
import public IdvPaths
import Installed

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
cleanAndBuild : HasIO io 
             => Version 
             -> (installedDir : String) 
             -> (buildPrefix : String) 
             -> io ()
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
            case List.find (== version) availableVersions of
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
install : HasIO io 
       => (installOver : Bool) 
       -> (installedDir : String) 
       -> Version 
       -> (buildPrefix : String) 
       -> io ()
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
  True <- cloneIfNeeded idrisRepoURL relativeCheckoutPath
    | False => exitError "Failed to clone Idris2 repository into local folder."
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

||| Assumes the current directory is an Idris 2 repository. Runs only
||| the install of the Idris 2 API.
installApi : HasIO io => io ()
installApi = do
  0 <- system "make install-api"
    | _ => exitError "Failed to install Idris2 API package."
  putStrLn ""
  putStrLn "Idris2 API package successfully installed."
  ignore $ clean

||| Select the given version if it is installed (as in set it as the version used
||| when the `idris2` command is executed). Then checkout that same version in the
||| checkout folder where builds are performed.
selectAndCheckout : HasIO io => (version : Version) -> io Bool
selectAndCheckout version = do
  Right _ <- selectVersion version
    | Left _  => pure False
  Right _ <- checkoutIfAvailable version
    | Left _ => pure False
  pure True

--
-- Commands
--

export
listVersionsCommand : HasIO io => io ()
listVersionsCommand = do
  True <- cloneIfNeeded idrisRepoURL relativeCheckoutPath
    | False => exitError "Failed to clone Idris2 repository into local folder."
  Just remoteVersions <- inDir relativeCheckoutPath fetchAndListVersions
    | Nothing => exitError "Failed to retrieve remote versions."
  Just installedVersions <- Installed.listVersions
    | Nothing => exitError "Failed to list local versions."
  systemInstall <- systemIdrisPath
  selectedVersion <- getSelectedVersion
  let selected = buildSelectedFn selectedVersion
  when (isJust systemInstall) $
    putStrLn $ (if selectedVersion == Nothing then "* " else "  ") ++ "system (installed)"
  traverse_ putStrLn $ printVersion . selected <$> zipMatch installedVersions remoteVersions
    where
      printVersion : (Bool, Maybe Version, Maybe Version) -> String
      printVersion (sel, Just v, Just _)  = (if sel then "* " else "  ") ++ "\{show v}  (installed)"
      printVersion (_, Nothing, Just v) = "  " ++ show v
      printVersion (sel, Just v, Nothing) = (if sel then "* " else "  ") ++ "\{show v}  (local only)"
      printVersion (_, Nothing, Nothing) = ""

      buildSelectedFn : (selectedVersion : Maybe Version) 
                     -> (Maybe Version, Maybe Version) 
                     -> (Bool, Maybe Version, Maybe Version)
      buildSelectedFn selectedVersion (l, r) = (l == selectedVersion, l, r)

export
installCommand : HasIO io => (version : Version) -> (cleanAfter : Bool) -> io ()
installCommand version cleanAfter = do
  createVersionsDir version
  buildAndInstall version cleanAfter

export
selectCommand : HasIO io => (version : Version) -> io ()
selectCommand version = do
  Right () <- selectVersion version
    | Left err => exitError err
  exitSuccess "Idris 2 version \{show version} selected."

||| Install the Idris 2 API (and the related version of Idris, if needed).
export
installAPICommand : HasIO io => (version : Version) -> io ()
installAPICommand version = do 
  -- we won't reinstall Idris 2 if not needed:
  unless !(selectAndCheckout version) $ do
    installCommand version False
    selectCommand version
  ignore $ inDir relativeCheckoutPath installApi
  pure ()

export
selectSystemCommand : HasIO io => io ()
selectSystemCommand = do
  Right () <- unselect
    | Left err => exitError err
  let proposedSymlinked = idrisSymlinkedPath
  Just installed <- systemIdrisPath
    | Nothing => exitError "Could not find system install of Idris 2. You might have to run this command with the IDRIS2 environment variable set to the location of the idris2 binary because it is not located at \{defaultIdris2Location}."
  Just linked <- pathExpansion proposedSymlinked
    | Nothing => exitError "Could not resolve symlinked location: \{proposedSymlinked}."
  True <- symlink installed linked
    | False => exitError "Failed to create symlink for Idris 2 system install."
  exitSuccess "System copy of Idris 2 selected."

