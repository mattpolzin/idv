module Data.Version

import Data.List
import Data.List1
import Data.String
import Data.String.Extra
import Data.Vect

||| A Semantic version.
public export
record Version where
  constructor V
  major, minor, patch : Nat
  ||| If the version is pre-release, the part of the version string following
  ||| a dash (e.g. 'alpha.1' in 0.1.0-alpha.1).
  prereleaseIdentifier : Maybe String
  ||| The full tag of the version. In the context of git this is exactly the
  ||| git tag. Elsewhere this field might hold other meaning.
  tag : String

%name Version version

export
Show Version where
  show (V major minor patch Nothing _) = "\{show major}.\{show minor}.\{show patch}"
  show (V major minor patch (Just pre) _) = "\{show major}.\{show minor}.\{show patch}-\{pre}"

export
Eq Version where
  (V major minor patch pre _) == (V i j k p _) = major == i && minor == j && patch == k && pre == p

export
Ord Version where
  compare (V major minor patch pre _) (V i j k p _) = case vectCompare [major, minor, patch] [i, j, k] of
                                                           EQ    => compare pre p
                                                           o@(_) => o
    where
      vectCompare : Vect 3 Nat -> Vect 3 Nat -> Ordering
      vectCompare = compare

version : (tag : String) -> (prereleaseIdentifier : Maybe String) -> Vect 3 Nat -> Version
version tag pre [x, y, z] = V x y z pre tag

||| Drop any pre-release info from the Version. Note that this does
||| not discard the tag if one is stored on the Version.
export
dropPrerelease : Version -> Version
dropPrerelease (V major minor patch _ tag) = (V major minor patch Nothing tag)

||| Parse a semantic version string.
export
parseVersion : String -> Maybe Version
parseVersion str = do
    let (primary, prerelease) = mapSnd (drop 1) $ break (== '-') str
    let components = split (== '.') $ dropPrefix primary
    nums <- sequence $ map parsePositive components
    version str (nonEmpty prerelease) <$> toVect 3 (forget nums)
  where
    dropPrefix : String -> String
    dropPrefix str with (strM str)
      dropPrefix "" | StrNil = ""
      dropPrefix _ | (StrCons x xs) =
        if x == 'v'
           then xs
           else str

    nonEmpty : String -> Maybe String
    nonEmpty str = case strM str of
                        StrNil        => Nothing
                        (StrCons _ _) => Just str

||| Parse the version as printed out by `idris2 --verison`.
|||
||| Important that this will return Nothing for pre-release
||| versions which can be spotted by the commmit hash following
||| the previous semantic version (0.4.0-b03395deb).
export
parseSpokenVersion : String -> Maybe Version
parseSpokenVersion = parseVersion . drop (length "Idris 2, version ")

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
    go : List Version 
      -> List Version 
      -> (acc : List (Maybe Version, Maybe Version)) 
      -> List (Maybe Version, Maybe Version)
    go [] [] acc = acc
    go [] (y :: ys) acc = go [] ys $ (Nothing, Just y) :: acc
    go (x :: xs) [] acc = go xs [] $ (Just x, Nothing) :: acc
    go (x :: xs) (y :: ys) acc = 
      case compare x y of
           LT => go xs (y :: ys) $ (Just x, Nothing) :: acc
           EQ => go xs ys $ (Just x, Just y) :: acc
           GT => go (x :: xs) ys $ (Nothing, Just y) :: acc

