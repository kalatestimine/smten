
{-# LANGUAGE EmptyDataDecls #-}
module Smten.Data.Array0 (
    PrimArray, primArray, primSelect,
    ) where

import Data.Array

import Smten.Plugin.Annotations

{-# ANN module PrimitiveModule #-}

data PrimArray a = PrimArray (Array Int a)

{-# NOINLINE primArray #-}
primArray :: [a] -> PrimArray a
primArray xs = {-# SCC "PRIM_PRIMARRAY" #-} PrimArray (listArray (0, length xs) xs)

{-# NOINLINE primSelect #-}
primSelect :: PrimArray a -> Int -> a
primSelect (PrimArray x) i = {-# SCC "PRIM_PRIMSELECT" #-} x ! i

