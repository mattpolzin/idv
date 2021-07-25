module System.Directory.Extra

import Data.String
import Data.String.Extra
import System
import System.Directory
import System.Path

export
createDirIfNeeded : HasIO io => (path : String) -> io Bool
createDirIfNeeded path =
  pure $ 
    case !(createDir path) of
         Right ()        => True
         Left FileExists => True
         _               => False

||| Expand path as shells tend to. Limited support so far.
|||
||| e.g. ~/ becomes absolute path of HOME directory.
export
pathExpansion : HasIO io => (path : String) -> io (Maybe String)
pathExpansion path with (strM path)
  pathExpansion ""  | StrNil           = pure $ Just ""
  pathExpansion _   | (StrCons '~' path) = do
    Just home <- getEnv "HOME"
      | Nothing => pure Nothing
    pure . Just $ home </> (drop 1 path)
  pathExpansion str | _                = pure $ Just str

export
inDir : HasIO io => (path : String) -> io a -> io (Maybe a)
inDir path ops = do
  Just cwd <- currentDir
    | Nothing => pure Nothing
  Just dir <- pathExpansion path
    | Nothing => pure Nothing
  putStrLn dir
  True <- changeDir dir
    | False => pure Nothing
  res <- ops
  ignore $ changeDir cwd
  pure (Just res)

