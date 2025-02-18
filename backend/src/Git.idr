module Git

import Data.List
import Data.Version
import System.Console.Extra
import System.Directory.Extra
import Data.String

||| Check if there is a repo in the current working directory.
repoExists : HasIO io => io Bool
repoExists = do
  [gitRemote] <- readLines (limit 1) True "git config --get remote.origin.url" -- "git status"
    | _ => pure False
  pure $ isSuffixOf "Idris2.git" $ trim gitRemote

clone : HasIO io => (repoURL : String) -> (path : String) -> io Bool
clone repoURL path = eatOutput False "git clone '\{repoURL}' '\{path}'"

||| Clone the given repository into the given path if the path does
||| not already contain a git repository.
|||
||| Returns True if the directory already contained a repo or if the
||| repo was successfully cloned into the requested path.
export
cloneIfNeeded : HasIO io => (description : String) -> (repoURL : String) -> (path : String) -> io Bool
cloneIfNeeded desc repoURL path = do
  Right () <- createDirIfNeeded path
    | Left _ => pure False
  Just False <- inDir path $ repoExists
    | _ => pure True
  putStrLn "Cloning \{desc} repository..."
  clone repoURL path

||| Fetch the repo in the current working directory.
export
fetch : HasIO io => io Bool
fetch = [ res == 0 | res <- ignoreOutput "git fetch --tags" ]

||| Pull the repo in the current working directory.
export
pull : HasIO io => io Bool
pull = [ res == 0 | res <- ignoreOutput "git pull --tags" ]

export
listTags : HasIO io => io (List String)
listTags = do
  tags <- readLines (limit 1000) False "git tag --list"
  pure tags

export
listBranches : HasIO io => io (List String)
listBranches = do
  branches <- readLines (limit 1000) False "git branch --list --all"
  pure branches

||| List the versions for the repo in the current working directory.
|||
||| Versions are all git tags formatted as <major>.<minor>.<patch> and
||| optionally prefixed with 'v'.
export
listVersions : HasIO io => io (List Version)
listVersions = pure $ mapMaybe parseVersion !listTags

||| Fetch git tags and then list versions.
export
fetchAndListVersions : HasIO io => io (List Version)
fetchAndListVersions = do
  ignore fetch
  listVersions

export
checkout : HasIO io => (tag : String) -> io Bool
checkout tag = [ res == 0 | res <- ignoreOutput "git checkout \{tag}" ]

export
checkoutAndPullBranch : HasIO io => (branch : String) -> io Bool
checkoutAndPullBranch branch = 
  pure $ !(checkout branch) && !pull

