
{-# LANGUAGE FlexibleInstances #-}

module Seri.Enoch.Prelude (
    apply, apply2,
    conE, varE, varE1, varE2,
    fst, snd, (==), (/=), (<), (>), (<=), (>=), (&&),
    ite,
 ) where

import Prelude hiding (fst, snd, Eq(..), (<), (>), (<=), (>=), (&&))
import qualified Prelude

import Seri.Lambda
import Seri.Enoch.Enoch

instance SeriableT () where
    serit _ = unitT

instance SeriableE () where
    pack () = TExp unitE
    unpack (TExp e) | e Prelude.== unitE = Just ()
    unpack _ = Nothing

instance SeriableT Integer where
    serit _ = integerT

instance SeriableE Integer where
    pack = TExp . integerE
    unpack (TExp (LitE (IntegerL i))) = Just i
    unpack _ = Nothing

instance SeriableT Char where
    serit _ = charT

instance SeriableE Char where
    pack = TExp . charE
    unpack (TExp (LitE (CharL c))) = Just c
    unpack _ = Nothing


instance SeriableT Bool where
    serit _ = boolT

instance SeriableE Bool where
    pack = TExp . boolE

    unpack (TExp x) | x Prelude.== trueE = Just True
    unpack (TExp x) | x Prelude.== falseE = Just False
    unpack _ = Nothing

instance SeriableT2 (->) where
    serit2 _ = ConT (name "->")

instance SeriableT2 (,) where
    serit2 _ = ConT (name "(,)")

instance (SeriableE a, SeriableE b) => SeriableE (a, b) where
    pack (a, b) =
      let TExp a' = pack a
          TExp b' = pack b
      in TExp $ tupE [a', b']
    unpack (TExp x) = do
      [a, b] <- deTupE x
      a' <- unpack (TExp a)
      b' <- unpack (TExp b)
      return (a', b')

apply :: TExp (a -> b) -> TExp a -> TExp b
apply (TExp f) (TExp x) = TExp $ AppE f [x]

apply2 :: TExp (a -> b -> c) -> TExp a -> TExp b -> TExp c
apply2 (TExp f) (TExp a) (TExp b) = TExp $ AppE f [a, b]

-- | Make a TExp with the given type out of a variable with the given name.
varE :: (SeriableT a) => String -> TExp a
varE nm =
  let t :: TExp a -> a
      t _ = undefined

      me = TExp $ VarE (Sig (name nm) (serit (t me)))
  in me

-- | Make a unary function from a variable name.
varE1 :: (SeriableT a, SeriableT b) => String -> TExp a -> TExp b
varE1 nm = 
  let f :: (SeriableT a, SeriableT b) => TExp (a -> b)
      f = varE nm
  in apply f

-- | Make a binary function from a variable name.
varE2 :: (SeriableT a, SeriableT b, SeriableT c)
         => String -> TExp a -> TExp b -> TExp c
varE2 nm =
  let f :: (SeriableT a, SeriableT b, SeriableT c) => TExp (a -> b -> c)
      f = varE nm
  in apply2 f

-- | Make a TExp with the given type out of a constructor with the given name.
conE :: (SeriableT a) => String -> TExp a
conE nm =
  let t :: TExp a -> a
      t _ = undefined

      me = TExp $ ConE (Sig (name nm) (serit (t me)))
  in me

instance Num (TExp Integer) where
    fromInteger = pack . fromInteger
    (+) = varE2 "Prelude.+"
    (*) = varE2 "Prelude.*"
    (-) = varE2 "Prelude.-"
    abs = error $ "todo: abs for TExp Integer"
    signum = error $ "todo: signum for TExp Integer"

-- This assumes there's a Seri instance of Eq for the object. Is that okay?
(==) :: (SeriableT a) => TExp a -> TExp a -> TExp Bool
(==) = varE2 "Prelude.=="

-- This assumes there's a Seri instance of Eq for the object. Is that okay?
(/=) :: (SeriableT a) => TExp a -> TExp a -> TExp Bool
(/=) = varE2 "Prelude./="

(<) :: TExp Integer -> TExp Integer -> TExp Bool
(<) = varE2 "Prelude.<"

(>) :: TExp Integer -> TExp Integer -> TExp Bool
(>) = varE2 "Prelude.>"

(<=) :: TExp Integer -> TExp Integer -> TExp Bool
(<=) = varE2 "Prelude.<="

(>=) :: TExp Integer -> TExp Integer -> TExp Bool
(>=) = varE2 "Prelude.>="

(&&) :: TExp Bool -> TExp Bool -> TExp Bool
(&&) = varE2 "Prelude.&&"

ite :: TExp Bool -> TExp a -> TExp a -> TExp a
ite (TExp p) (TExp a) (TExp b) = TExp $ ifE p a b

fst :: (SeriableT a, SeriableT b) => TExp (a, b) -> TExp a
fst = varE1 "Prelude.fst"

snd :: (SeriableT a, SeriableT b) => TExp (a, b) -> TExp b
snd = varE1 "Prelude.snd"
