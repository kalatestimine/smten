
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE MagicHash #-}
{-# OPTIONS_GHC -O #-}
module Smten.GHC.Classes (
    (&&), (||), not,
    Eq(..)
    ) where

import GHC.Prim
import GHC.Types
import Smten.Data.Char0

infix 4 ==, /=
infixr 3 &&
infixr 2 ||


-- Note: this has to match the definition from Prelude
class Eq a where
    (==) :: a -> a -> Bool
    (==) x y = not (x /= y)

    (/=) :: a -> a -> Bool
    (/=) x y = not (x == y)

instance Eq Int where
    (==) = eqInt
    (/=) = neInt

{-# INLINE eqInt #-}
{-# INLINE neInt #-}
eqInt, neInt :: Int -> Int -> Bool
(I# x) `eqInt` (I# y) = x ==# y
(I# x) `neInt` (I# y) = x /=# y

instance Eq () where
    (==) () () = True

instance (Eq a, Eq b) => Eq (a, b) where
    (==) (a, b) (c, d) = (a == c) && (b == d)

instance (Eq a, Eq b, Eq c) => Eq (a, b, c) where
    (==) (a1, a2, a3) (b1, b2, b3) = (a1 == b1) && (a2 == b2) && (a3 == b3)

instance (Eq a) => Eq [a] where
    (==) [] [] = True
    (==) (a:as) (b:bs) = a == b && as == bs
    (==) _ _ = False

instance Eq Bool where
    (==) True True = True
    (==) True False = False
    (==) False True = False
    (==) False False = True

instance Eq Char where 
   (==) = char_eq

instance Eq Ordering where
   (==) LT LT = True
   (==) EQ EQ = True
   (==) GT GT = True
   (==) _ _ = False


(&&) :: Bool -> Bool -> Bool
(&&) True x = x
(&&) False _ = False

(||) :: Bool -> Bool -> Bool
(||) True _ = True
(||) False x = x

not :: Bool -> Bool
not True = False
not False = True

