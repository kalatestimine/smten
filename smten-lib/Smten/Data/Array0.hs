
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE NoImplicitPrelude, RebindableSyntax #-}
module Smten.Data.Array0 (
    PrimArray, primArray, primSelect,
    ) where

import Smten.Prelude
import Smten.Plugin.Annotations

{-# ANN module PrimitiveModule #-}

data PrimArray a

primArray :: [a] -> PrimArray a
primArray = primitive "Smten.Data.Array0.primArray"

primSelect :: PrimArray a -> Int -> a
primSelect = primitive "smten.Data.Array0.primSelect"
