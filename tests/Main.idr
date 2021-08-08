module Main

import Test.Golden

tests : TestPool
tests = MkTestPool "idv" [] Nothing [
  "list", "select", "help"
]

main : IO ()
main = do
  runner [tests]

