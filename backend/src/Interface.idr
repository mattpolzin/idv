module Interface

import Data.List
import Data.Maybe
import Data.Version
import Data.String
import System
import System.Console.Extra
import System.Directory
import System.Directory.Extra
import System.File
import System.File.Extra

import Git
import public IdvPaths
import Installed
import Interp

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

createVersionsDir : HasIO io => Version -> io ()
createVersionsDir version = do
  Just resolvedVersionsDir <- pathExpansion $ versionPath version
    | Nothing => exitError "Could not resolve install directory for new Idris2 version."
  Right () <- createDirIfNeeded $ resolvedVersionsDir
    | Left err => exitError "Could not create install directory for new Idris2 version (\{show err}))."
  pure ()

||| Assumes the current working directory is a git repository.
updateMainBranch : HasIO io => io ()
updateMainBranch = do
  True <- checkoutAndPullBranch "main"
    | False => exitError "Could not update Idris2 repository prior to building a new version."
  pure ()

||| Assumes the current working directory is a git repository with a clean target in the Makefile.
clean : HasIO io => io Bool
clean = [ res == 0 | res <- System.system "make clean" ]

||| Builds the current repository _using_ the executable for the
||| given version. This means you must have already installed the
||| given version into the versions folder (possibly as a bootstrap
||| build).
||| Assumes the current working directory is an Idris repository.
build : HasIO io => (idrisExecutable : Version) -> (installedDir : String) -> (buildPrefix : String) -> io Bool
build version installedDir buildPrefix = 
  [ res == 0 | res <- System.system "PREFIX=\"\{buildPrefix}\" IDRIS2_BOOT=\"\{installedDir}\" make" ]

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
checkoutIfAvailable : HasIO io => BuildTarget -> Version -> io (Either String ())
checkoutIfAvailable target version = do
  fromMaybe (Left "Failed to switch to checkout directory.") <$>
    changeDirAndCheckout
      where
        checkoutIdris : io (Either String ())
        checkoutIdris = do
          availableVersions <- listVersions
          case List.find (== version) availableVersions of
               Nothing => pure $ Left "Version \{version} is not one of the available versions: \{availableVersions}."
               (Just resolvedVersion) => do 
                 True <- checkout resolvedVersion.tag
                   | False => pure $ Left "Could not check out requested version of Idris2."
                 pure $ Right ()

        checkoutLspLib : io (Either String ())
        checkoutLspLib = do
          True <- checkout (lspLibRev version)
            | False => pure $ Left "Could not check out required version of the Idris2 LSP Library."
          pure $ Right ()

        checkoutLsp : io (Either String ())
        checkoutLsp = do
          let desiredBranchName = idrisLspBranchName version
          availableBranches <- listBranches
          case List.find (desiredBranchName `isInfixOf`) availableBranches of
               Nothing => pure $ Left "The LSP does not have a branch for version \{version} Available branches: \{availableBranches}."
               (Just resolvedBranch) => do 
                 True <- checkout resolvedBranch
                   | False => pure $ Left "Could not check out requested version of the Idris2 LSP."
                 pure $ Right ()

        checkoutTarget : io (Either String ())
        checkoutTarget =
          case target of
               Idris  => checkoutIdris
               LSP    => checkoutLsp
               LSPLib => checkoutLspLib

        changeDirAndCheckout : io (Maybe (Either String ()))
        changeDirAndCheckout =
          inDir (relativeCheckoutPath target) $ do
            updateMainBranch
            checkoutTarget

||| Assumes the current working directory is an Idris repository.
bootstrapBuild : HasIO io => (resolvedVersion : Version) -> (buildPrefix : String) -> io ()
bootstrapBuild version buildPrefix = do
  True <- go
    | False => exitError "Failed to build Idris2 version \{version}."
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
        res <- System.system "make clean && PREFIX=\"\{buildPrefix}\" SCHEME=\"\{exec}\" make bootstrap"
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
  0 <- installCompiler
    | _ => exitError "Failed to install Idris2 \{version}."
  -- Idris2 v0.4.0 was when install-with-src was added.
  when (version >= (V 0 4 0 Nothing "")) $ do
    0 <- installLibsWithSrc
      | _ => exitError "Failed to install Idris2 libraries \{version}."
    pure ()
  putStrLn ""
  putStrLn "Idris2 version \{version}\{caveat} successfully installed to \{buildPrefix}."
  pure ()

  where
    executableOverride : String
    executableOverride = if installOver
                            then "IDRIS2_BOOT=\"\{installedDir}\""
                            else ""

    caveat : String
    caveat = if installOver
                then ""
                else " (bootstrap build)"

    installCompiler : io Int
    installCompiler = System.system "PREFIX=\"\{buildPrefix}\" \{executableOverride} make install"

    installLibsWithSrc : io Int
    installLibsWithSrc = System.system "PREFIX=\"\{buildPrefix}\" \{executableOverride} make install-with-src-libs"

buildAndInstall : HasIO io => Version -> (cleanAfter : Bool) -> io ()
buildAndInstall version cleanAfter = do
  putStrLn "Building Idris2 \{version}"
  let target = Idris
  True <- cloneIfNeeded "Idris 2" idrisRepoURL (relativeCheckoutPath target)
    | False => exitError "Failed to clone Idris2 repository into local folder."
  Right _ <- checkoutIfAvailable target version
    | Left err => exitError err
  moveDirRes <- inDir (relativeCheckoutPath target) $ do
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
    exitError "Failed to install version \{version}."

buildAndInstallLspLib : HasIO io => (idrisVersion : Version) -> io ()
buildAndInstallLspLib version = do
  putStrLn "Building Idris2 LSP-lib (dependency for Idris2 LSP)."
  let target = LSPLib
  True <- cloneIfNeeded "LSP-lib" idrisLspLibRepoURL (relativeCheckoutPath target)
    | False => exitError "Failed to clone Idris 2 LSP Library repository into local folder."
  Right _ <- checkoutIfAvailable target version
    | Left err => exitError err
  moveDirRes <- inDir (relativeCheckoutPath target) $ do
    let proposedBuildPrefix = buildPrefix version
    Just buildPrefix <- pathExpansion proposedBuildPrefix
      | Nothing => exitError "Could not resolve build prefix directory: \{proposedBuildPrefix}."
    0 <- installLspLib buildPrefix
      | _ => exitError "Failed to build & install LSP Library."
    -- clean up
    ignore $ clean
  unless (isJust moveDirRes) $
    exitError "Failed to install LSP Library for version \{version}."

  where
    installLspLib : (buildPrefix : String) -> io Int
    installLspLib buildPrefix = System.system "idris2 --install-with-src"

buildAndInstallLsp : HasIO io => (idrisVersion : Version) -> io ()
buildAndInstallLsp version = do
  when (version >= v 0 7 0) $
    buildAndInstallLspLib version
  putStrLn "Building Idris2 LSP \{version}"
  let target = LSP
  True <- cloneIfNeeded "LSP Server" idrisLspRepoURL (relativeCheckoutPath target)
    | False => exitError "Failed to clone Idris 2 LSP repository into local folder."
  Right _ <- checkoutIfAvailable target version
    | Left err => exitError err
  moveDirRes <- inDir (relativeCheckoutPath target) $ do
    let proposedInstalledDir = installedLspPath version
    let proposedBuildPrefix = buildPrefix version
    Just installedDir <- pathExpansion proposedInstalledDir
      | Nothing => exitError "Could not resolve install directory: \{proposedInstalledDir}."
    Just buildPrefix <- pathExpansion proposedBuildPrefix
      | Nothing => exitError "Could not resolve build prefix directory: \{proposedBuildPrefix}."
    0 <- installLsp buildPrefix
      | _ => exitError "Failed to build & install LSP."
    -- clean up
    ignore $ clean
  unless (isJust moveDirRes) $ 
    exitError "Failed to install LSP for version \{version}."
  putStrLn ""
  putStrLn "Idris2 LSP successfully installed."

  where
    installLsp : (buildPrefix : String) -> io Int
    installLsp buildPrefix = System.system "PREFIX=\"\{buildPrefix}\" make install"

||| Uninstall the given version. Assumes that version exists.
uninstall : HasIO io => Version -> io ()
uninstall version = do
  Just installPath <- pathExpansion $ versionPath version
    | Nothing => exitError "Failed to locate an install path for version \{version}."
  putStrLn "uninstalling from \{installPath}..."
  -- TODO: make cross-platform remove recursive. current standard lib options won't do it.
  0 <- System.system $ "rm -rf " ++ installPath
    | _ => exitError "Failed to remove install directory."
  pure ()

||| Assumes the current directory is an Idris 2 repository. Runs only
||| the install of the Idris 2 API.
installApi : HasIO io => Version -> io ()
installApi version = do
  let proposedBuildPrefix = buildPrefix version
  Just buildPrefix <- pathExpansion proposedBuildPrefix
    | Nothing => exitError "Could not resolve build prefix directory: \{proposedBuildPrefix}."
  0 <- System.system "PREFIX=\"\{buildPrefix}\" make install-\{maybeWithSrc}"
    | _ => exitError "Failed to install Idris2 API package."
  putStrLn ""
  putStrLn "Idris2 API package successfully installed."
  ignore $ clean

  where
    -- Idris2 v0.4.0 was when install-with-src was added.
    maybeWithSrc : String
    maybeWithSrc = if version >= (V 0 4 0 Nothing "")
                      then "with-src-api"
                      else "api"

||| Select the given version if it is installed (as in set it as the version used
||| when the `idris2` command is executed). Then checkout that same version in the
||| checkout folder where builds are performed.
selectAndCheckout : HasIO io => (version : Version) -> io Bool
selectAndCheckout version = do
  Right _ <- selectVersion version
    | Left _  => pure False
  Right _ <- checkoutIfAvailable Idris version
    | Left _ => pure False
  pure True

--
-- Commands
--

readSelectedExternalPath : HasIO io => io (Maybe String)
readSelectedExternalPath = let (>>=) = Prelude.(>>=) @{Monad.Compose} in do 
  selected <- pathExpansion selectedExternalIdrisSourcePath
  either (const Nothing) (head' . snd) <$> readFilePage 0 (limit 1) selected

export
listVersionsCommand : HasIO io => io ()
listVersionsCommand = do
  True <- cloneIfNeeded "Idris 2" idrisRepoURL (relativeCheckoutPath Idris)
    | False => exitError "Failed to clone Idris2 repository into local folder."
  Just remoteVersions <- inDir (relativeCheckoutPath Idris) fetchAndListVersions
    | Nothing => exitError "Failed to retrieve remote versions."
  Just installedVersions <- Installed.listVersions
    | Nothing => exitError "Failed to list local versions."
  systemInstall   <- getSystemVersion
  systemIdrisPath <- IdvPaths.systemIdrisPath
  packInstall     <- getPackVersion
  packIdrisPath   <- IdvPaths.packIdrisPath
  selectedVersion <- getSelectedVersion
  selectedExternalPath <- readSelectedExternalPath
  let isSystemSelected = isJust selectedExternalPath && systemIdrisPath == selectedExternalPath
  let isPackSelected   = isJust selectedExternalPath && packIdrisPath   == selectedExternalPath
  let selectedInstalled = if isSystemSelected || isPackSelected 
                             then (False,)
                             else buildSelectedFn selectedVersion
  whenJust systemInstall $ \systemVersion => do
    putStrLn $ (if isSystemSelected then "* " else "  ") ++ "system (installed @ v\{systemVersion})"
  whenJust packInstall $ \packVersion => do
    putStrLn $ (if isPackSelected then "* " else "  ") ++ "pack   (installed @ v\{packVersion})"
  traverse_ putStrLn $ printVersion . selectedInstalled <$> zipMatch installedVersions remoteVersions
    where
      printVersion : (Bool, Maybe Version, Maybe Version) -> String
      printVersion (sel, Just v, Just _)  = (if sel then "* " else "  ") ++ "\{v}  (installed)"
      printVersion (_, Nothing, Just v) = "  " ++ show v
      printVersion (sel, Just v, Nothing) = (if sel then "* " else "  ") ++ "\{v}  (local only)"
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
uninstallCommand : HasIO io => (version : Version) -> io ()
uninstallCommand version =
  case !(isInstalled version) of
       Left err    => exitError err
       Right False => exitError "Version \{version} is not installed."
       Right True  =>
         when !(confirm "Are you sure you want to uninstall version \{version}?") $ do
           uninstall version
           exitSuccess "Uninstalled version \{version}."

||| When switching Idris installs, store the source path of the install using this
||| function. This is not the path of the source-code, it is the location where the Idris2
||| binary can be found.
trackExternalSourcePath : HasIO io => (sourcePath : String) -> io ()
trackExternalSourcePath sourcePath = whenJust !(pathExpansion selectedExternalIdrisSourcePath) $ 
                                       \selectedSourcePath => ignore $ writeFile selectedSourcePath sourcePath

untrackExternalSourcePath : HasIO io => io ()
untrackExternalSourcePath = whenJust !(pathExpansion selectedExternalIdrisSourcePath) $ 
                              \selectedSourcePath => ignore $ removeFile selectedSourcePath

export
selectCommand : HasIO io => (version : Version) -> io ()
selectCommand version = do
  Right () <- selectVersion version
    | Left err => exitError err
  untrackExternalSourcePath
  exitSuccess "Idris 2 version \{version} selected."

selectOtherIdris : HasIO io => (idrisPath : String) -> (lspPath : Maybe String) -> io (Either String ())
selectOtherIdris idrisPath lspPath = do
  Right () <- unselect
    | Left err => pure $ Left err
  let proposedIdrisSymlinked = idrisSymlinkedPath
  Just linkedIdris <- pathExpansion proposedIdrisSymlinked
    | Nothing => pure $ Left "Could not resolve symlinked location: \{proposedIdrisSymlinked}."
  True <- symlink idrisPath linkedIdris
    | False => pure $ Left "Failed to create symlink for Idris 2 system install."
  trackExternalSourcePath idrisPath
  case lspPath of
       Nothing => pure $ Right ()
       Just installedLsp => do
          let proposedLspSymlinked = idrisLspSymlinkedPath
          Just linkedLsp <- pathExpansion proposedLspSymlinked
            | Nothing => pure $ Left "Could not resolve symlinked LSP location: \{proposedLspSymlinked}."
          True <- symlink installedLsp linkedLsp
            | False => pure $ Left "Failed to create symlink for Idris 2 LSP system install."
          pure $ Right ()

selectSystemIdris : HasIO io => io (Either String ())
selectSystemIdris = do
  Just installedIdrisPath <- systemIdrisPath
    | Nothing => pure $ Left """
                             Could not find system install of Idris 2.
                             You might have to run this command with the IDRIS2 environment variable \
                             set to the location of the idris2 binary because it is not located at \{defaultIdris2Location}.
                             """
  selectOtherIdris installedIdrisPath !systemIdrisLspPath

export
selectSystemCommand : HasIO io => io ()
selectSystemCommand = do
  Right () <- selectSystemIdris
    | Left err => exitError err
  exitSuccess "System install of Idris 2 selected."

export
selectPackCommand : HasIO io => io ()
selectPackCommand = do
  Just installedPackIdrisPath <- packIdrisPath
    | Nothing => exitError """
                           Could not find pack install of Idris 2.
                           You might have to run this command with the PACK_DIR environment variable \
                           set because it is not located at \{defaultPackDirectory}.
                           """
  Right () <- selectOtherIdris installedPackIdrisPath !packIdrisLspPath
    | Left err => exitError err
  exitSuccess "Pack install of Idris 2 selected."

||| Select the given version and print messages to the effect of
||| failing to switch _back_ to that version if unsuccessful.
switchBack : HasIO io => (actionMsg : String) -> (prevVersion : Version) -> io (Either String ())
switchBack actionMsg prevVersion = do
  Right True <- isInstalled prevVersion
    | Right False => pure $ Left "Successfully \{actionMsg} but failed to switch back to Idris version \{prevVersion} because it couldn't be found at the expected install location"
    | Left err    => pure $ Left err
  Right () <- selectVersion prevVersion
    | Left err => pure $ Left "Successfully \{actionMsg} but failed to switch back to Idris version \{prevVersion} with error: \{err}"
  pure $ Right ()

||| Install the Idris 2 API (and the related version of Idris, if needed).
export
installApiCommand : HasIO io => (version : Version) -> io ()
installApiCommand version = do 
  selectedVersion <- getSelectedVersion
  -- we won't reinstall Idris 2 if not needed:
  unless !(selectAndCheckout version) $ do
    installCommand version False
    Right () <- selectVersion version
      | Left err => exitError err
    pure ()
  Just _ <- inDir (relativeCheckoutPath Idris) (installApi version)
    | Nothing => exitError "Failed to switch to checkout branch and install Idris 2 API."
  -- if we know we used to have a different version of Idris selected, switch back.
  whenJust selectedVersion $ \prevVersion => do
    putStrLn "Switching back to previously selected Idris2 version (\{show prevVersion})"
    case !(switchBack "installed Idris 2 API version \{version} package" prevVersion) of
         Right () => pure ()
         Left err => exitError err

||| Install the Idris 2 LSP (and the related version of Idris, if needed).
export
installLspCommand : HasIO io => (version : Version) -> io ()
installLspCommand version = do
  when (version < (V 0 4 0 Nothing "")) $
    exitError "The Idris 2 LSP is not supported prior to Idris 2 v0.4.0."
  selectedVersion <- getSelectedVersion
  -- don't reinstall Idris 2 and its API unless needed:
  unless !selectIdrisWithAPI $ do
    installApiCommand version
    Right () <- selectVersion version
      | Left err => exitError err
    pure ()
  buildAndInstallLsp version
  whenJust selectedVersion $ \prevVersion =>
    case !(switchBack "installed Idris 2 LSP for version \{version}" prevVersion) of
         Right () => pure ()
         Left err => exitError err

  where
    ||| Select the requested Idris version and verify it has
    ||| the API installed.
    selectIdrisWithAPI : io Bool
    selectIdrisWithAPI = do
      Right () <- selectVersion version
        | _ => do putStrLn "Idris 2 version \{version} will be installed prior to installing the LSP server."
                  pure False
      case !(hasApiInstalled version) of
           Right True => pure True
           _ => do putStrLn "The Idris 2 API for version \{version} will be installed prior to installing the LSP server."
                   pure False

