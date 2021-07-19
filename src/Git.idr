module Git

import System
import System.File
import System.Directory
import Data.Maybe

createDirIfNeeded : HasIO io => (path : String) -> io Bool
createDirIfNeeded path =
  pure $ 
    case !(createDir path) of
         Right ()        => True
         Left FileExists => True
         _               => False

inDir : HasIO io => (path : String) -> io a -> io (Maybe a)
inDir path ops = do
  Just cwd <- currentDir
    | Nothing => pure Nothing
  True <- changeDir path
    | False => pure Nothing
  res <- ops
  ignore $ changeDir cwd
  pure (Just res)

||| Eat the stdout and return the exit status.
eatOutput : HasIO io => (cmd : String) -> io Int
eatOutput cmd = do
  Right h <- popen cmd Read
    | Left e => pure (-1)
  Right c <- fGetChar h
    | Left _ => do putStrLn "file error"
                   pure (-1)
  pclose h

repoExists : HasIO io => (repoURL : String) -> (path : String) -> io Bool
repoExists repoURL path = do
  Just 0 <- inDir path $ eatOutput "git status"
    | Nothing => do putStrLn "here"
                    pure False
    | (Just x) => do putStrLn $ "there " ++ (show x)
                     pure False
  pure True

clone : HasIO io => (repoURL : String) -> (path : String) -> io Bool
clone repoURL path = [ res == 0 | res <- system "git clone '\{repoURL}' '\{path}'" ]

export
cloneIfNeeded : HasIO io => (repoURL : String) -> (path : String) -> io Bool
cloneIfNeeded repoURL path = do
  True <- createDirIfNeeded path
    | False => pure False
  False <- repoExists repoURL path
    | True => pure True
  clone repoURL path

