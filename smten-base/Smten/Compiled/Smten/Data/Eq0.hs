
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Compiled.Smten.Data.Eq0 (int_eq, integer_eq) where

import qualified Prelude as P
import Smten.Compiled.Smten.Smten.Base
import Smten.Compiled.Smten.Data.Bool0
import Smten.Runtime.SymbolicOf
import Smten.Runtime.Types

int_eq :: Int -> Int -> Bool
int_eq = symapp2 P.$ \av bv ->
    if (av :: P.Int) P.== bv    
        then True
        else False

integer_eq :: Integer -> Integer -> Bool
integer_eq = eq_Integer
