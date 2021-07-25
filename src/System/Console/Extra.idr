module System.Console.Extra

import Data.List
import Data.String
import System.File
import System.Info
import System

import public Data.Fuel

ignoreStdOut : String
ignoreStdOut = 
  if isWindows
     then ">NUL"
     else ">/dev/null"

ignoreStdErr : String
ignoreStdErr = 
  if isWindows
     then "2>NUL"
     else "2>/dev/null"

redirectStdErr : String
redirectStdErr = "2>&1"

||| Ignore the stdout and stderr from the given command and return
||| the status code resulting from running the command.
export
ignoreOutput : HasIO io => (cmd : String) -> io Int
ignoreOutput cmd = system $ unwords [cmd, ignoreStdOut, redirectStdErr]

||| Eat the stdout and return True if there was any
||| output to stdout (and stderror if ignoreStdErr is False).
export
eatOutput : HasIO io => (ignoreStdErr : Bool) -> (cmd : String) -> io Bool
eatOutput ignStdErr cmd = do
  let fullCmd = unwords [cmd, (if ignStdErr then ignoreStdErr else redirectStdErr)]
  Right h <- popen fullCmd Read
    | Left _ => pure False
  Right l <- fGetLine h
    | Left _ => pure False
  pclose h
  pure $ l /= ""

||| Read lines from the given command's stdout.
export
readLines : HasIO io => Fuel -> (ignoreStdErr : Bool) -> (cmd : String) -> io (List String)
readLines fuel ignStdErr cmd = do
    let fullCmd = unwords [cmd, (if ignStdErr then ignoreStdErr else redirectStdErr)]
    Right h <- popen fullCmd Read
      | _ => pure []
    lines <- readLines' fuel h []
    pclose h
    pure lines
  where
    readLines' : Fuel -> File -> List String -> io (List String)
    readLines' Dry _ acc = pure $ reverse acc
    readLines' (More fuel) h acc = do
      Right l <- fGetLine h
        | Left _ => readLines' Dry h acc
      readLines' fuel h (l :: acc)
