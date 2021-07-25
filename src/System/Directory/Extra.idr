module System.Directory.Extra

import System.Directory

export
createDirIfNeeded : HasIO io => (path : String) -> io Bool
createDirIfNeeded path =
  pure $ 
    case !(createDir path) of
         Right ()        => True
         Left FileExists => True
         _               => False

export
inDir : HasIO io => (path : String) -> io a -> io (Maybe a)
inDir path ops = do
  Just cwd <- currentDir
    | Nothing => pure Nothing
  True <- changeDir path
    | False => pure Nothing
  res <- ops
  ignore $ changeDir cwd
  pure (Just res)
