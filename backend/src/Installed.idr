||| Functions for working with installed Idris 2 versions.
||| These are the things found in the ./versions directory
||| under the Idv install.
module Installed

import Data.Either
import Data.List
import Data.Version
import Data.String
import System.Console.Extra
import System.Directory
import System.Directory.Extra
import System.File.Extra
import System.Path

import IdvPaths
import Interp

versionsDir : String
versionsDir =
  idvLocation </> relativeVersionsPath

||| List the local (i.e. installed) versions of Idris 2.
export
listVersions : HasIO io => io (Maybe (List Version))
listVersions = let (>>=) = Prelude.(>>=) @{Monad.Compose} in do
  pathExpansion versionsDir >>= versions
    where
      replaceUnderscores : String -> String
      replaceUnderscores = pack . replaceOn '_' '.' . unpack

      parseFolderEntries : List String -> List Version
      parseFolderEntries = mapMaybe (parseVersion . replaceUnderscores)

      versionFolders : (path : String) -> io (Maybe (List String))
      versionFolders = (map eitherToMaybe) . listDir

      versions : (path : String) -> io (Maybe (List Version))
      versions path = map parseFolderEntries <$> versionFolders path

||| Check if the given version is installed.
export
isInstalled : HasIO io => Version -> io (Either String Bool)
isInstalled version = do
  Just localVersions <- listVersions
    | Nothing => pure $ Left "Could not look up local versions."
  pure $ 
    case find (== version) localVersions of
         Nothing      => Right False
         Just version => Right True

||| Check if the given Idris version has the Idris 2 API package installed.
export
hasApiInstalled : HasIO io => Version -> io (Either String Bool)
hasApiInstalled version = do
  versionInstalled <- isInstalled version
  Just libPath <- pathExpansion (idrisApiLibPath version)
    | Nothing => pure $ Left "could not locate Idris 2 libdir."
  pure $ Right !(exists libPath)

||| Remove the symlink that points to the "selected" Idris 2 executable.
export
unselect : HasIO io => io (Either String ())
unselect = do
  Just lnFile <- pathExpansion $ idrisSymlinkedPath
    | Nothing => pure $ Left "Could not resolve Idris 2 symlink path."
  Just lnLspFile <- pathExpansion $ idrisLspSymlinkedPath
    | Nothing => pure $ Left "Could not resolve Idris 2 LSP symlink path."
  Right () <- removeFile lnFile
    | Left FileNotFound => pure $ Right () -- no problem here, job done.
    | Left err => pure $ Left "Failed to remove symlink file (to let system Idris 2 installation take precedence): \{err}."
  Right () <- removeFile lnLspFile
    | Left FileNotFound => pure $ Right () -- no problem here, job done.
    | Left err => pure $ Left "Failed to remove LSP symlink file (to let system Idris 2 installation take precedence): \{err}."
  pure $ Right ()

||| Attempt to select the given version. Fails if the version
||| requested is not installed.
export
selectVersion : HasIO io => Version -> io (Either String ())
selectVersion proposedVersion = do
  Just localVersions <- listVersions
    | Nothing => pure $ Left "Could not look up local versions."
  case find (== proposedVersion) localVersions of
       Nothing      => pure $ Left "Idris 2 version \{proposedVersion} is not installed.\nInstalled versions: \{sort localVersions}."
       Just version => do
         Right () <- unselect
           | Left err => pure $ Left err
         let proposedIdrisInstalled = installedIdrisPath version
         let proposedIdrisSymlinked = idrisSymlinkedPath
         let proposedLspInstalled = installedLspPath version
         let proposedLspSymlinked = idrisLspSymlinkedPath
         Prelude.(>>) @{Monad.Compose}
           (setLink version proposedIdrisInstalled proposedIdrisSymlinked)
           (setLink version proposedLspInstalled proposedLspSymlinked)

  where
    setLink : Version -> (proposedInstalledLocation : String) -> (proposedSymlinkedLocation : String) -> io (Either String ())
    setLink version proposedInstalledLocation proposedSymlinkedLocation =  do
      Just installed <- pathExpansion proposedInstalledLocation 
        | Nothing => pure $ Left "Could not resolve install location: \{proposedInstalledLocation}."
      Just linked <- pathExpansion proposedSymlinkedLocation 
        | Nothing => pure $ Left "Could not resolve symlinked location: \{proposedSymlinkedLocation}."
      True <- exists installed
        | False => pure $ Right () -- nothing to link to
      True <- symlink installed linked
        | False => pure $ Left "Failed to create symlink for Idris 2 version \{version}."
      pure $ Right ()

||| Get the version of the Idris installed at the given path.
export
getVersion : HasIO io => (idrisExecPath : String) -> io (Maybe Version)
getVersion idrisExecPath = do
  Just symPath <- pathExpansion idrisExecPath
    | Nothing => pure Nothing
  True <- exists symPath
    | False => pure Nothing
  out <- (map trim) <$> readLines (limit 1) True "\{symPath} --version"
  pure $ head' out >>= parseSpokenVersion

export
getSystemVersion : HasIO io => io (Maybe Version)
getSystemVersion = 
  let (=<<) = Prelude.(=<<) @{Monad.Compose}
  in  getVersion =<< systemIdrisPath

export
getPackVersion : HasIO io => io (Maybe Version)
getPackVersion = 
  let (=<<) = Prelude.(=<<) @{Monad.Compose}
  in  getVersion =<< packIdrisPath

export
getSelectedVersion : HasIO io => io (Maybe Version)
getSelectedVersion = getVersion idrisSymlinkedPath

||| Use the given version for an operation and then switch back.
export
withVersion : HasIO io => Version -> io (Either String a) -> io (Either String a)
withVersion version op = do
  previousVersion <- getSelectedVersion
  Right () <- selectVersion version
    | Left err => pure $ Left err
  res <- op
  Right () <- undoSelect previousVersion
    | Left err => pure $ Left err
  pure res
    where
      undoSelect : (previous : Maybe Version) -> io (Either String ())
      undoSelect Nothing  = unselect
      undoSelect (Just v) = selectVersion version

