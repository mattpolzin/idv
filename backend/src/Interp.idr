||| Interpolation implementations
module Interp

import System.File.Error
import Data.Version
import Data.String.Extra

export
Interpolation Version where
  interpolate = show

export
Interpolation a => Interpolation (List a) where
  interpolate = join ", " . map interpolate

export
Interpolation FileError where
  interpolate (GenericFileError x) = show x
  interpolate FileReadError = "failed to read file"
  interpolate FileWriteError = "failed to write file"
  interpolate FileNotFound = "file was not found"
  interpolate PermissionDenied = "file has the wrong permissions"
  interpolate FileExists = "file already exists"

