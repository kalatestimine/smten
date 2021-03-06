

{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | Implementation of Smten primitive Integer type
module Smten.Runtime.Integer (
    Integer(..),
  ) where

import qualified Prelude as P

import Smten.Runtime.Formula
import Smten.Runtime.Formula.Finite
import Smten.Runtime.Formula.PartialF
import Smten.Runtime.SmtenHS
import Smten.Runtime.SymbolicOf

type Integer = IntegerF

instance Finite IntegerF where
    ite_finite p a b = ite0 (finiteF p) a b
    unreachable_finite = unreachable

-- Do integer symapp for integers not in ite form.
-- This works by making an ite tree which (lazily) enumerates the entire space
-- of integers:
--   if y == 0
--      then f 0
--      else if y == 1
--        then f 1
--        else ...
--
-- TODO: Because this is infinite, and we don't actually perform lazy
-- evaluation, this will never work.
-- We can make it work more often by bounding the range we enumerate, and
-- having an explicit error outside that range with a hopefully useful error
-- message.
nonIteIntegerSymapp :: SmtenHS0 a => (P.Integer -> a) -> IntegerFF -> a
nonIteIntegerSymapp f y =
  let -- allin l h x
      --    Do symapp for x assuming x >= l and x < h.
      lookin l h x
        | l P.== (h P.- 1) = f l
        | P.otherwise =
            let m = (l P.+ h) `P.div` 2
            in ite0 (finiteF P.$ leq_IntegerFF x (integerFF (m P.- 1)))
                           (lookin l m x)
                           (lookin m h x)

      -- lookabove l i 
      --    Do symapp for x assuming x >= l
      lookabove l i x =
         let h = l P.+ i
         in ite0 (finiteF P.$ leq_IntegerFF x (integerFF h))
                    (lookin l h x)
                    (lookabove h (i P.* 2) x)

      -- lookbelow h i
      --    Do symapp for x assuming x < h
      lookbelow h i x =
         let l = h P.- i
         in ite0 (finiteF P.$ leq_IntegerFF x (integerFF l))
                    (lookbelow l (i P.* 2) x)
                    (lookin l h x)
            
  in ite0 (finiteF P.$ leq_IntegerFF y (integerFF (P.negate 1)))
              (lookbelow 0 1 y)
              (lookabove 0 1 y)
        
instance SymbolicOf P.Integer IntegerFF where
    tosym = integerFF

    symapp f x =
      case x of
        IntegerFF i -> f i
        Add_IntegerFF a b _ -> symapp (\av -> (symapp (\bv -> f (av P.+ bv))) b) a
        Sub_IntegerFF a b _ -> symapp (\av -> (symapp (\bv -> f (av P.- bv))) b) a
        Ite_IntegerFF p a b _ -> ite0 (finiteF p) (symapp f a) (symapp f b)
        Var_IntegerFF {} -> nonIteIntegerSymapp f x
        Unreachable_IntegerFF -> unreachable
        

instance SymbolicOf P.Integer IntegerF where
    tosym = integerF

    symapp f x =
      case deIntegerF x of
        (TrueFF, IntegerFF i, _) -> f i
        (p, a, b) -> ite0 (finiteF p) (symapp f a) (symapp f b)


instance P.Num IntegerF where
    fromInteger = integerF
    (+) = P.error "Smten IntegerF P.Num (+) not supported"
    (*) = P.error "Smten IntegerF P.Num (*) not supported"
    abs = P.error "Smten IntegerF P.Num abs not supported"
    signum = P.error "Smten IntegerF P.Num signum not supported"

