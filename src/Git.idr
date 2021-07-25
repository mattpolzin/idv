module Git

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import Data.Vect
import System
import System.Console.Extra
import System.Directory.Extra

repoExists : HasIO io => (repoURL : String) -> (path : String) -> io Bool
repoExists repoURL path = do
  Just True <- inDir path $ eatOutput True "git status"
    | _ => pure False
  pure True

clone : HasIO io => (repoURL : String) -> (path : String) -> io Bool
clone repoURL path = eatOutput False "git clone '\{repoURL}' '\{path}'"

||| Clone the given repository into the given path if the path does
||| not already contain a git repository.
|||
||| Returns True if the directory already contained a repo or if the
||| repo was successfully cloned into the requested path.
export
cloneIfNeeded : HasIO io => (repoURL : String) -> (path : String) -> io Bool
cloneIfNeeded repoURL path = do
  True <- createDirIfNeeded path
    | False => pure False
  False <- repoExists repoURL path
    | True => pure True
  putStrLn "Cloning Idris 2 repository..."
  clone repoURL path

export
fetch : HasIO io => (path : String) -> io Bool
fetch path = [ True | _ <- inDir path $ eatOutput True "git fetch --tags" ]

listTags : HasIO io => (path : String) -> io (List String)
listTags path = do
  Just tags <- inDir path $ readLines (limit 1000) False "git tag --list"
    | _ => pure []
  pure tags

public export
data Version : Type where
  V : (major : Nat) -> (minor : Nat) -> (patch : Nat) -> Version

export
Show Version where
  show (V major minor patch) = "\{show major}.\{show minor}.\{show patch}"

version : Vect 3 Nat -> Version
version [x, y, z] = V x y z

parseVersion : String -> Maybe Version
parseVersion str = do
    let components = split (== '.') $ dropPrefix str
    nums <- sequence $ map parsePositive components
    version <$> toVect 3 (forget nums)
  where
    dropPrefix : String -> String
    dropPrefix str with (strM str)
      dropPrefix "" | StrNil = ""
      dropPrefix _ | (StrCons x xs) =
        if x == 'v'
           then xs
           else str

export
listVersions : HasIO io => (path : String) -> io (List Version)
listVersions path = pure $ mapMaybe parseVersion !(listTags path)

