
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.GHC.Integer.Type (
   plusInteger, minusInteger, timesInteger,
   quotInteger, remInteger, divInteger, modInteger,
   divModInteger, quotRemInteger,
   absInteger, signumInteger, eqInteger,
   leInteger, smallInteger,
    ) where

import GHC.Prim
import GHC.Types(Bool(..))
import qualified GHC.Integer as P
import Smten.Smten.Base
import Smten.Plugin.Annotations

{-# ANN module PrimitiveModule #-}

{-# NOINLINE plusInteger #-}
plusInteger :: Integer -> Integer -> Integer
plusInteger = P.plusInteger

{-# NOINLINE minusInteger #-}
minusInteger :: Integer -> Integer -> Integer
minusInteger = P.minusInteger

{-# NOINLINE timesInteger #-}
timesInteger :: Integer -> Integer -> Integer
timesInteger = P.timesInteger

{-# NOINLINE absInteger #-}
absInteger :: Integer -> Integer
absInteger = P.absInteger

{-# NOINLINE signumInteger #-}
signumInteger :: Integer -> Integer
signumInteger = P.signumInteger

{-# NOINLINE eqInteger #-}
eqInteger :: Integer -> Integer -> Bool
eqInteger = P.eqInteger

{-# NOINLINE leInteger #-}
leInteger :: Integer -> Integer -> Bool
leInteger = P.leInteger

{-# NOINLINE smallInteger #-}
smallInteger :: Int# -> Integer
smallInteger = P.smallInteger

{-# NOINLINE quotInteger #-}
quotInteger :: Integer -> Integer -> Integer
quotInteger = P.quotInteger

{-# NOINLINE remInteger #-}
remInteger :: Integer -> Integer -> Integer
remInteger = P.remInteger

{-# NOINLINE modInteger #-}
modInteger :: Integer -> Integer -> Integer
modInteger = P.modInteger

{-# NOINLINE divInteger #-}
divInteger :: Integer -> Integer -> Integer
divInteger = P.divInteger

{-# NOINLINE divModInteger #-}
divModInteger :: Integer -> Integer -> (# Integer, Integer #)
divModInteger = P.divModInteger

{-# NOINLINE quotRemInteger #-}
quotRemInteger :: Integer -> Integer -> (# Integer, Integer #)
quotRemInteger = P.quotRemInteger

