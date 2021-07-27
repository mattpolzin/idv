module Local

import Data.List
import Data.Either
import Data.Version
import System.Directory
import System.Directory.Extra
import System.Path

import IdvPaths

versionsDir : String
versionsDir =
  idvLocation </> relativeVersionsPath

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

