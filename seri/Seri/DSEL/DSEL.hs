
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}

module Seri.DSEL.DSEL ( 
    ExpT(..), seriET,
    apply, apply2,
    varET, varET1, varET2,
    fst, snd, (==), (/=), (<), (>), (<=), (>=), (&&),
    ite,
  ) where

import Prelude hiding (fst, snd, Eq(..), (<), (>), (<=), (>=), (&&))
import qualified Prelude

import Seri.Name
import Seri.Sig
import Seri.Type
import Seri.Dec hiding (prelude)
import Seri.Exp
import Seri.ExpH
import Seri.Inline
import Seri
import Seri.TH

prelude :: Env
prelude = $(loadenvth [seridir] (seridir >>= return . (++ "/Prelude.sri")))

data ExpT a = ExpT ExpH

varET :: (SeriT a) => Env -> String -> ExpT a
varET env nm =
  let t :: ExpT a -> a
      t _ = undefined
    
      me = ExpT $ inline env (varE (Sig (name nm) (seriT (t me))))
  in me

-- | Make a unary function from a variable name.
varET1 :: (SeriT a, SeriT b) => Env -> String -> ExpT a -> ExpT b
varET1 env nm = 
  let f :: (SeriT a, SeriT b) => ExpT (a -> b)
      f = varET env nm
  in apply f


-- | Make a binary function from a variable name.
varET2 :: (SeriT a, SeriT b, SeriT c)
         => Env -> String -> ExpT a -> ExpT b -> ExpT c
varET2 env nm =
  let f :: (SeriT a, SeriT b, SeriT c) => ExpT (a -> b -> c)
      f = varET env nm
  in apply2 f

apply :: ExpT (a -> b) -> ExpT a -> ExpT b
apply (ExpT f) (ExpT x) = ExpT $ appEH f x

apply2 :: ExpT (a -> b -> c) -> ExpT a -> ExpT b -> ExpT c
apply2 (ExpT f) (ExpT a) (ExpT b) = ExpT $ appsEH f [a, b]


instance Num (ExpT Integer) where
    fromInteger = ExpT . seriEH 
    (+) = varET2 prelude "Prelude.+"
    (*) = varET2 prelude "Prelude.*"
    (-) = varET2 prelude "Prelude.-"
    abs = error $ "todo: abs for ExpT Integer"
    signum = error $ "todo: signum for ExpT Integer"

-- This assumes there's a Seri instance of Eq for the object. Is that okay?
(==) :: (SeriT a) => ExpT a -> ExpT a -> ExpT Bool
(==) = varET2 prelude "Prelude.=="

-- This assumes there's a Seri instance of Eq for the object. Is that okay?
(/=) :: (SeriT a) => ExpT a -> ExpT a -> ExpT Bool
(/=) = varET2 prelude "Prelude./="

(<) :: ExpT Integer -> ExpT Integer -> ExpT Bool
(<) = varET2 prelude "Prelude.<"

(>) :: ExpT Integer -> ExpT Integer -> ExpT Bool
(>) = varET2 prelude "Prelude.>"

(<=) :: ExpT Integer -> ExpT Integer -> ExpT Bool
(<=) = varET2 prelude "Prelude.<="

(>=) :: ExpT Integer -> ExpT Integer -> ExpT Bool
(>=) = varET2 prelude "Prelude.>="

ite :: ExpT Bool -> ExpT a -> ExpT a -> ExpT a
ite (ExpT p) (ExpT a) (ExpT b) = ExpT $ ifEH p a b

fst :: (SeriT a, SeriT b) => ExpT (a, b) -> ExpT a
fst = varET1 prelude "Prelude.fst"

snd :: (SeriT a, SeriT b) => ExpT (a, b) -> ExpT b
snd = varET1 prelude "Prelude.snd"

seriET :: (SeriEH a) => a -> ExpT a
seriET = ExpT . seriEH

