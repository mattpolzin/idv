module Data.Version

import Data.List1
import Data.String
import Data.Vect

public export
record Version where
  constructor V
  major, minor, patch : Nat
  tag : String

%name Version version

export
Show Version where
  show (V major minor patch _) = "\{show major}.\{show minor}.\{show patch}"

export
Eq Version where
  (V major minor patch _) == (V k j i _) = major == k && minor == j && patch == i

export
Ord Version where
  compare (V major minor patch _) (V k j i _) = 
    case compare major k of
         LT => LT
         GT => GT
         EQ => case compare minor j of
                    LT => LT
                    GT => GT
                    EQ => compare patch i

version : (tag : String) -> Vect 3 Nat -> Version
version tag [x, y, z] = V x y z tag

export
parseVersion : String -> Maybe Version
parseVersion str = do
    let components = split (== '.') $ dropPrefix str
    nums <- sequence $ map parsePositive components
    version str <$> toVect 3 (forget nums)
  where
    dropPrefix : String -> String
    dropPrefix str with (strM str)
      dropPrefix "" | StrNil = ""
      dropPrefix _ | (StrCons x xs) =
        if x == 'v'
           then xs
           else str

