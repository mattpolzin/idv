module Local

import Data.Either
import Data.List
import Data.Version
import System.Console.Extra
import System.Directory
import System.Directory.Extra
import System.File
import System.File.Extra
import System.Path

import IdvPaths

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

||| Remove the symlink that points to the "selected" Idris 2 executable.
export
unselect : HasIO io => io (Either String ())
unselect = do
  Just lnFile <- pathExpansion $ idrisSymlinkedPath
    | Nothing => pure $ Left "Could not resolve Idris 2 symlink path."
  Right () <- removeFile lnFile
    | Left FileNotFound => pure $ Right () -- no problem here, job done.
    | Left err => pure $ Left "Failed to remove symlink file (to let system Idris 2 installation take precedence): \{show err}."
  pure $ Right ()

||| Attempt to select the given version. Fails if the version
||| requested is not installed.
export
selectVersion : HasIO io => Version -> io (Either String ())
selectVersion proposedVersion = do
  Just localVersions <- listVersions
    | Nothing => pure $ Left "Could not look up local versions."
  case find (== proposedVersion) localVersions of
       Nothing      => pure $ Left "Idris 2 version \{show proposedVersion} is not installed.\nInstalled versions: \{show $ sort localVersions}."
       Just version => do
         Right () <- unselect
           | Left err => pure $ Left err
         let proposedInstalled = installedIdrisPath version
         let proposedSymlinked = idrisSymlinkedPath
         Just installed <- pathExpansion proposedInstalled
           | Nothing => pure $ Left "Could not resolve install location: \{proposedInstalled}."
         Just linked <- pathExpansion proposedSymlinked
           | Nothing => pure $ Left "Could not resolve symlinked location: \{proposedSymlinked}."
         True <- symlink installed linked
           | False => pure $ Left "Failed to create symlink for Idris 2 version \{show version}."
         pure $ Right ()

export
getSelectedVersion : HasIO io => io (Maybe Version)
getSelectedVersion = do
  Just symPath <- pathExpansion idrisSymlinkedPath
    | Nothing => pure Nothing
  True <- exists symPath
    | False => pure Nothing
  out <- readLines (limit 1) True "\{symPath} --version"
  pure $ head' out >>= parseSpokenVersion

-- TODO: write function that temporarily switches versions for 1 io operation.
-- ||| Use the given version for an operation and then switch back.
-- export
-- withVersion : HasIO io => Version -> io (Either String a) -> io (Either String a)
-- withVersion version op = ?withVersion_rhs

