
{-# LANGUAGE IncoherentInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Smten.Runtime.Array (
    PrimArray, primArray, primSelect,
    P.Integer,
    ) where

import Prelude as P

import Data.Array
import Data.Functor
import Data.List(genericLength)

import Smten.Runtime.SmtenHS as S

data PrimArray a = PrimArray (Array P.Integer a)
                 | PrimArray_Prim (Assignment -> PrimArray a) (PrimArray a)
                 | PrimArray_Ite S.Bool (PrimArray a) (PrimArray a)
                 | PrimArray_Error String

instance SmtenHS1 PrimArray where
    realize1 m (PrimArray x) = PrimArray (realize m <$> x)
    realize1 m (PrimArray_Prim r _) = realize m (r m)
    realize1 m (PrimArray_Ite p a b) = __caseTrue (realize m p) (realize m a) (realize m b)

    error1 = PrimArray_Error

    primitive1 = PrimArray_Prim
    ite1 = PrimArray_Ite
    sapp1 f x = 
      case x of
        PrimArray {} -> f x
        PrimArray_Ite p a b -> ite p (sapp1 f a) (sapp1 f b)
        PrimArray_Error msg -> error0 msg
        _ -> error "TODO: sapp1 on symbolic PrimArray"

instance Haskelly (PrimArray a) (PrimArray a) where
    stohs = id
    frhs = id

instance (Haskelly h s) => Haskelly (PrimArray h) (PrimArray s) where
    stohs (PrimArray arr) = PrimArray (stohs <$> arr)
    frhs (PrimArray arr) = PrimArray (frhs <$> arr)

primArray :: [a] -> PrimArray a
primArray xs = PrimArray (listArray (0, genericLength xs) xs)

primSelect :: PrimArray a -> P.Integer -> a
primSelect (PrimArray arr) i = arr ! i

