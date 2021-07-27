module Data.Version

import Data.List
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

||| Take two version lists and zip them up post-sorting
||| such that versions exist to the left or right only
||| if the given version was in the first or second list
||| (respectively).
|||
||| [1.0.0, 1.1.0, 2.0.0] `zipmatch` [1.0.0, 2.0.0, 3.0.0]
||| results in:
||| [(1.0.0, 1.0.0), (1.1.0, Nothing), (2.0.0, 2.0.0), (Nothing, 3..0.0)]
export
zipMatch : List Version -> List Version -> List (Maybe Version, Maybe Version)
zipMatch xs ys = go (sort xs) (sort ys) []
  where
    go : List Version -> List Version -> (acc : List (Maybe Version, Maybe Version)) -> List (Maybe Version, Maybe Version)
    go [] [] acc = acc
    go [] (y :: ys) acc = go [] ys $ (Nothing, Just y) :: acc
    go (x :: xs) [] acc = go xs [] $ (Just x, Nothing) :: acc
    go (x :: xs) (y :: ys) acc = 
      case compare x y of
           LT => go xs (y :: ys) $ (Just x, Nothing) :: acc
           EQ => go xs ys $ (Just x, Just y) :: acc
           GT => go (x :: xs) ys $ (Nothing, Just y) :: acc

