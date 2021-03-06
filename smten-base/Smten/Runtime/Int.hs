

{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -fprof-auto-top #-}

-- | Implementation of primitive Int# type for Smten.
module Smten.Runtime.Int (
    Int#(..), __isLitInt#, toHSInt#,
    (/=#), (==#), (>=#), (<=#), (>#), (<#),
    (+#), (-#), (*#), negateInt#,
    quotInt#, remInt#, quotRemInt#,
    primIntApp, int#,
    traceS_CharF,
  ) where

import qualified Prelude as P
import qualified GHC.Types as P
import qualified GHC.Prim as P

import Smten.Runtime.Bool
import Smten.Runtime.Formula.BoolF
import Smten.Runtime.Formula.PartialF
import Smten.Runtime.Formula.Finite
import Smten.Runtime.SmtenHS
import Smten.Runtime.IntFF

newtype Int# = Int# (PartialF IntFF)

-- Assuming the Int# is concrete, return it's value.
toHSInt# :: Int# -> P.Int#
toHSInt# (Int# (PartialF TrueFF (IntFF v) _)) = v


ite_IntF :: BoolF -> Int# -> Int# -> Int#
ite_IntF (BoolF p) (Int# a) (Int# b) = Int# (itePF p a b)

unreachable_IntF :: Int#
unreachable_IntF = Int# unreachablePF

-- TODO: this forgets that 'p' is finite.
primIntApp :: (SmtenHS0 a) => (P.Int# -> a) -> Int# -> a
primIntApp f (Int# (PartialF TrueFF (IntFF v) _)) = f v
primIntApp f (Int# (PartialF p a b)) = ite0 (finiteF p) (applyToIntFF' f a) (primIntApp f (Int# b))

instance SmtenHS0 Int# where
    ite0 p a b = iteS p a b (ite_IntF p a b)
    unreachable0 = unreachable_IntF
    traceS0 (Int# x) = traceSPF trace_IntFF x

int# :: P.Int# -> Int#
int# v = Int# (finitePF (IntFF v))

__isLitInt# :: P.Int# -> Int# -> Bool
__isLitInt# v (Int# a) = BoolF (unaryPF (isLit_IntFF v) a)

instance P.Num Int# where
    fromInteger x =
      case P.fromInteger x of
        P.I# v -> int# v

    (+) = P.error "Smten Int P.Num (+) not supported"
    (*) = P.error "Smten Int P.Num (*) not supported"
    abs = P.error "Smten Int P.Num abs not supported"
    signum = P.error "Smten Int P.Num signum not supported"

(/=#) :: Int# -> Int# -> Bool
(/=#) (Int# a) (Int# b) = BoolF (binaryPF neq_IntFF a b)

(==#) :: Int# -> Int# -> Bool
(==#) (Int# a) (Int# b) = BoolF (binaryPF eq_IntFF a b)

(>=#) :: Int# -> Int# -> Bool
(>=#) (Int# a) (Int# b) = BoolF (binaryPF geq_IntFF a b)

(<=#) :: Int# -> Int# -> Bool
(<=#) (Int# a) (Int# b) = BoolF (binaryPF leq_IntFF a b)

(>#) :: Int# -> Int# -> Bool
(>#) (Int# a) (Int# b) = BoolF (binaryPF gt_IntFF a b)

(<#) :: Int# -> Int# -> Bool
(<#) (Int# a) (Int# b) = BoolF (binaryPF lt_IntFF a b)

(+#) :: Int# -> Int# -> Int#
(+#) (Int# a) (Int# b) = Int# (binaryPF add_IntFF a b)

(-#) :: Int# -> Int# -> Int#
(-#) (Int# a) (Int# b) = Int# (binaryPF sub_IntFF a b)

(*#) :: Int# -> Int# -> Int#
(*#) (Int# a) (Int# b) = Int# (binaryPF mul_IntFF a b)

quotInt# :: Int# -> Int# -> Int#
quotInt# (Int# a) (Int# b) = Int# (binaryPF quot_IntFF a b)

remInt# :: Int# -> Int# -> Int#
remInt# (Int# a) (Int# b) = Int# (binaryPF rem_IntFF a b)

quotRemInt# :: Int# -> Int# -> (# Int#, Int# #)
quotRemInt# a b = (# quotInt# a b, remInt# a b #)

negateInt# :: Int# -> Int#
negateInt# (Int# a) = Int# (unaryPF negate_IntFF a)

-- Trace an Int#, interpreted as a Char#
traceS_CharF :: Int# -> P.String
traceS_CharF (Int# x) = traceSPF trace_CharFF x

