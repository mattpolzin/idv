module System.File.Extra

import System
import System.Info

-- TODO: interface with C functions for symlinks in POSIX & Windows environments.
--       for now, I'll skip the C library and just call out to system.
export
symlink : HasIO io => (from : String) -> (to : String) -> io Bool
symlink from to = 
  [ res == 0 | res <- if isWindows
       then putStrLn "Unsupported (so far)" >> pure 1
       else system "ln -s \"\{from}\" \"\{to}\"" ]

