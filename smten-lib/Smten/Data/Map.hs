
-- Implementation of binary balanced tree based on Data.Map source from
-- haskell library.

{-# LANGUAGE NoImplicitPrelude, RebindableSyntax #-}
module Smten.Data.Map where

import Smten.Prelude

data Map k a = Tip | Bin Size k a (Map k a) (Map k a)

type Size = Integer

instance (Show k, Show a) => Show (Map k a) where
    show m = show (toList m)

lookup :: (Ord k) => k -> Map k v -> Maybe v
lookup k t
  = case t of
      Tip -> Nothing
      Bin _ kx x l r ->
        case compare k kx of
          LT -> Smten.Data.Map.lookup k l
          GT -> Smten.Data.Map.lookup k r
          EQ -> Just x
      
insert :: (Ord k) => k -> v -> Map k v -> Map k v
insert kx x t =
  case t of
    Tip -> singleton kx x
    Bin sz ky y l r ->
        case compare kx ky of
           LT -> balance ky y (insert kx x l) r
           GT -> balance ky y l (insert kx x r)
           EQ -> Bin sz kx x l r

delta :: Integer
delta = 5

ratio :: Integer
ratio = 2

balance :: k -> a -> Map k a -> Map k a -> Map k a
balance k x l r =
  let sizeL = size l
      sizeR = size r
      sizeX = sizeL + sizeR + 1
  in if (sizeL + sizeR <= 1)
        then Bin sizeX k x l r
        else if (sizeR >= delta*sizeL)
                then rotateL k x l r
                else if (sizeL >= delta*sizeR)
                    then rotateR k x l r
                    else Bin sizeX k x l r

rotateL :: a -> b -> Map a b -> Map a b -> Map a b
rotateL k x l r@(Bin _ _ _ ly ry) =
  if (size ly < ratio * size ry)
     then singleL k x l r
     else doubleL k x l r
rotateL _ _ _ _ = error "rotateL Tip"

rotateR :: a -> b -> Map a b -> Map a b -> Map a b
rotateR k x l@(Bin _ _ _ ly ry) r =
  if (size ry < ratio * size ly)
      then singleR k x l r
      else doubleR k x l r
rotateR _ _ _ _ = error "rotateR Tip"

singleL :: a -> b -> Map a b -> Map a b -> Map a b
singleL k1 x1 t1 (Bin _ k2 x2 t2 t3) = bin k2 x2 (bin k1 x1 t1 t2) t3
singleL _ _ _ _ = error "singleL Tip"

singleR :: a -> b -> Map a b -> Map a b -> Map a b
singleR k1 x1 (Bin _ k2 x2 t1 t2) t3 = bin k2 x2 t1 (bin k1 x1 t2 t3)
singleR _ _ _ _ = error "singleR Tip"

doubleL :: a -> b -> Map a b -> Map a b -> Map a b
doubleL k1 x1 t1 (Bin _ k2 x2 (Bin _ k3 x3 t2 t3) t4) = bin k3 x3 (bin k1 x1 t1 t2) (bin k2 x2 t3 t4)
doubleL _ _ _ _ = error "doubleL"

doubleR :: a -> b -> Map a b -> Map a b -> Map a b
doubleR k1 x1 (Bin _ k2 x2 t1 (Bin _ k3 x3 t2 t3)) t4 = bin k3 x3 (bin k2 x2 t1 t2) (bin k1 x1 t3 t4)
doubleR _ _ _ _ = error "doubleR"

bin :: k -> a -> Map k a -> Map k a -> Map k a
bin k x l r = Bin (size l + size r + 1) k x l r


size :: Map k v -> Size
size Tip = 0
size (Bin sz _ _ _ _) = sz

empty :: Map k v
empty = Tip

singleton :: k -> v -> Map k v
singleton k v = Bin 1 k v empty empty

fromList :: (Ord k) => [(k, v)] -> Map k v
fromList ((k, v):xs) = insert k v (fromList xs)
fromList _ = empty

toList :: Map k v -> [(k, v)]
toList (Bin _ k v a b) = concat [toList a, [(k, v)], toList b]
toList _ = []
