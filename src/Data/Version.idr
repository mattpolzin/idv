module Data.Version

import Data.List1
import Data.String
import Data.Vect

public export
data Version : Type where
  V : (major : Nat) -> (minor : Nat) -> (patch : Nat) -> Version

export
Show Version where
  show (V major minor patch) = "\{show major}.\{show minor}.\{show patch}"

export
Eq Version where
  (V major minor patch) == (V k j i) = major == k && minor == j && patch == i

export
Ord Version where
  compare (V major minor patch) (V k j i) = 
    case compare major k of
         LT => LT
         GT => GT
         EQ => case compare minor j of
                    LT => LT
                    GT => GT
                    EQ => compare patch i

version : Vect 3 Nat -> Version
version [x, y, z] = V x y z

export
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

