
{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleInstances #-}

module Smten.Runtime.SmtenHS (
    SmtenHS0(..), SmtenHS1(..), SmtenHS2(..), SmtenHS3(..), SmtenHS4(..),
    ite, iterealize, realize,
    merge, emptycase, unusedfield,
    ) where

import Smten.Runtime.Model
import Smten.Runtime.StableNameEq
import Smten.Runtime.FiniteFormula
import Smten.Runtime.Formula

class SmtenHS0 a where
    ite0 :: BoolF -> a -> a -> a
    realize0 :: Model -> a -> a

class SmtenHS1 m where
    ite1 :: (SmtenHS0 a) => BoolF -> m a -> m a -> m a
    realize1 :: (SmtenHS0 a) => Model -> m a -> m a

instance (SmtenHS0 a, SmtenHS1 m) => SmtenHS0 (m a) where
    ite0 = ite1
    realize0 = realize1

class SmtenHS2 m where
    ite2 :: (SmtenHS0 a, SmtenHS0 b) => BoolF -> m a b -> m a b -> m a b
    realize2 :: (SmtenHS0 a, SmtenHS0 b) => Model -> m a b -> m a b

instance (SmtenHS0 a, SmtenHS2 m) => SmtenHS1 (m a) where
    ite1 = ite2
    realize1 = realize2

class SmtenHS3 m where
    ite3 :: (SmtenHS0 a, SmtenHS0 b, SmtenHS0 c) => BoolF -> m a b c -> m a b c -> m a b c
    realize3 :: (SmtenHS0 a, SmtenHS0 b, SmtenHS0 c) => Model -> m a b c -> m a b c

instance (SmtenHS0 a, SmtenHS3 m) => SmtenHS2 (m a) where
    ite2 = ite3
    realize2 = realize3

class SmtenHS4 m where
    ite4 :: (SmtenHS0 a, SmtenHS0 b, SmtenHS0 c, SmtenHS0 d) => BoolF -> m a b c d -> m a b c d -> m a b c d
    realize4 :: (SmtenHS0 a, SmtenHS0 b, SmtenHS0 c, SmtenHS0 d) => Model -> m a b c d -> m a b c d


instance (SmtenHS0 a, SmtenHS4 m) => SmtenHS3 (m a) where
    ite3 = ite4
    realize3 = realize4

{-# INLINEABLE ite #-}
ite :: (SmtenHS0 a) => BoolF -> a -> a -> a
ite p a b 
  | isTrueF p = a
  | isFalseF p = b
  | a `stableNameEq` b = a
  | otherwise = ite0 p a b

{-# INLINEABLE iterealize #-}
iterealize :: (SmtenHS0 a) => BoolF -> a -> a -> Model -> a
iterealize p a b m = ite (realize m p) (realize m a) (realize m b)
    
realize :: (SmtenHS0 a) => Model -> a -> a
realize m x = m_cached m realize0 x

-- merge
-- Merge all the arguments into a single object.
-- Assumptions: It is always that case that at least one of the guards is True.
--  Which also means: this must be given a non-empty list.
merge :: (SmtenHS0 a) => [(BoolF, a)] -> a
merge [] = error "merge on empty list"
merge [(_, v)] = v
merge ((p, v):vs) = ite p v (merge vs)

instance SmtenHS0 BoolFF where
    ite0 = error "BoolFF.ite"
    realize0 m x =
      case x of
        TrueFF -> x
        FalseFF -> x
        IteFF p a b -> iteFF (realize m p) (realize m a) (realize m b)
        AndFF a b -> andFF (realize m a) (realize m b)
        OrFF a b -> orFF (realize m a) (realize m b)
        NotFF p -> notFF (realize m p)
        VarFF n -> boolFF (lookupBool m n)
        IEqFF a b -> ieqFF (realize m a) (realize m b)
        ILeqFF a b -> ileqFF (realize m a) (realize m b)

instance SmtenHS0 IntegerFF where
    ite0 = error "IntegerFF.ite"
    realize0 m x = 
      case x of
        IntegerFF {} -> x
        IAddFF a b -> iaddFF (realize m a) (realize m b)
        ISubFF a b -> isubFF (realize m a) (realize m b)
        IIteFF p a b -> iiteFF (realize m p) (realize m a) (realize m b)
        IVarFF v -> integerFF (lookupInteger m v)
              
instance SmtenHS0 BoolF where
    ite0 = iteF
    realize0 m (BoolF a b x_) =
      case (realize m a, realize m b) of
        (TrueFF, _) -> trueF
        (FalseFF, FalseFF) -> falseF
        (FalseFF, TrueFF) -> realize m x_

instance SmtenHS0 IntegerF where
   ite0 = Integer_Ite
   realize0 m x = 
      case x of
         IntegerF {} -> x
         Integer_Add a b -> add_Integer (realize m a) (realize m b)
         Integer_Sub a b -> sub_Integer (realize m a) (realize m b)
         Integer_Ite p a b -> iterealize p a b m
         Integer_Var n -> IntegerF (lookupInteger m n)
   
instance SmtenHS0 (BitF n) where
    realize0 m x = 
      case x of
        BitF {} -> x
        Bit_Add a b -> add_Bit (realize m a) (realize m b)
        Bit_Sub a b -> sub_Bit (realize m a) (realize m b)
        Bit_Mul a b -> mul_Bit (realize m a) (realize m b)
        Bit_Or a b -> or_Bit (realize m a) (realize m b)
        Bit_And a b -> and_Bit (realize m a) (realize m b)
        Bit_Shl a b -> shl_Bit (realize m a) (realize m b)
        Bit_Lshr a b -> lshr_Bit (realize m a) (realize m b)
        Bit_Concat w a b -> concat_Bit w (realize m a) (realize m b)
        Bit_Not a -> not_Bit (realize m a)
        Bit_SignExtend by x -> sign_extend_Bit by (realize m x)
        Bit_Extract wx hi lo x -> extract_Bit wx hi lo (realize m x)
        Bit_Ite p a b -> iterealize p a b m
        Bit_Var w n -> BitF (lookupBit m w n)
    ite0 = Bit_Ite

instance SmtenHS2 (->) where
    realize2 m f = \x -> realize m (f (realize m x))
    ite2 p fa fb = \x -> ite p (fa x) (fb x)

emptycase :: a
emptycase = error "inaccessable case"

unusedfield :: String -> a
unusedfield msg = error ("unused field access " ++ msg)

