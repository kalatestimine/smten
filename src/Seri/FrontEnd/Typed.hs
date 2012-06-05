
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}


module Seri.FrontEnd.Typed 
    (
        Typed(..), typedas,
        SeriType(..), SeriType1(..), SeriType2(..), SeriType3(..),
        integerE, caseE, conE, conE', varE, dvarE, lamE, appE,
        primitive, match, lamM, method,
        conP, appP, wildP, integerP,
        enved,
    )
    where

import qualified Language.Haskell.TH as TH

import Seri.Lambda.IR
import Seri.Lambda.Env

data Typed x t = Typed {
    typed :: x
} deriving (Show)

typedas :: Typed a t -> Typed b t -> Typed b t
typedas _ x = x

class SeriType a where
    seritype :: a -> Type

class SeriType1 m where
    seritype1 :: m a -> Type

instance (SeriType1 m, SeriType a) => SeriType (m a) where  
    seritype m =
        let ta :: m a -> a
            ta _ = undefined
        in AppT (seritype1 m) (seritype (ta m))

class SeriType2 m where
    seritype2 :: m a b -> Type

instance SeriType2 (->) where
    seritype2 _ = ConT "->"

instance (SeriType2 m, SeriType a) => SeriType1 (m a) where
    seritype1 ma =
        let ta :: m a b -> a
            ta _ = undefined
        in AppT (seritype2 ma) (seritype (ta ma))

class SeriType3 m where
    seritype3 :: m a b c -> Type
    
instance (SeriType3 m, SeriType a) => SeriType2 (m a) where
    seritype2 ma = 
        let ta :: m a b c -> a
            ta _ = undefined
        in AppT (seritype3 ma) (seritype (ta ma))

usetype :: (SeriType a) => Typed x a -> (Type -> b) -> b
usetype e f = f (seritype (gettype e))
    where gettype :: Typed x a -> a
          gettype _ = undefined

-- withtype f 
--  Calls the function f with the Type corresponding to the type of the
--  returned expression.
withtype :: (SeriType a) => (Type -> Typed x a) -> Typed x a
withtype f = r where r = usetype r f

primitive :: (SeriType a) => Name -> Typed Exp a
primitive p = withtype $ \t -> Typed $ PrimE (Sig p t)

integerE :: Integer -> Typed Exp Integer
integerE x = Typed $ IntegerE x

caseE :: (SeriType b) => Typed Exp a -> [Typed Match (a -> b)] -> Typed Exp b
caseE (Typed e) matches = Typed $ CaseE e (map typed matches)

match :: Typed Pat a -> Typed Exp b -> Typed Match (a -> b)
match (Typed p) (Typed e) = Typed $ Match p e

conP :: (SeriType a) => Typed Exp a -> Name -> Typed Pat a
conP _ n = withtype $ \t -> Typed $ ConP (Sig n t)

appP :: Typed Pat (a -> b) -> Typed Pat a -> Typed Pat b
appP (Typed f) (Typed x) = Typed $ AppP f x

wildP :: (SeriType a) => Typed Pat a
wildP = withtype $ \t -> Typed (WildP t)

integerP :: Integer -> Typed Pat Integer
integerP i = Typed $ IntegerP i

appE :: (SeriType b) => Typed Exp (a -> b) -> Typed Exp a -> Typed Exp b
appE (Typed f) (Typed x) = Typed $ AppE f x

lamE :: (SeriType a, SeriType (a -> b)) => Name -> (Typed Exp a -> Typed Exp b) -> Typed Exp (a -> b)
lamE n f =
    let ft :: (Typed Exp a -> Typed Exp b) -> Typed Exp a
        ft = undefined

        sig = usetype (ft f) (\t -> Sig n t)
    in Typed $ LamE sig (typed $ f (varE n))

lamM :: (SeriType a) => Name -> (Typed Pat a -> Typed Exp a -> Typed Match b) -> Typed Match b
lamM n f =
    let ft :: (Typed Pat a -> Typed Exp a -> Typed Match b) -> Typed Exp a
        ft = undefined

        sig = usetype (ft f) (\t -> Sig n t)
    in f (Typed $ VarP sig) (varE n)

varE :: (SeriType a) => Name -> Typed Exp a
varE nm = withtype $ \t -> Typed $ VarE (Sig nm t) Bound

dvarE :: (SeriType a) => Typed Exp a -> (Typed Exp a -> VarInfo) -> Name -> Typed Exp a
dvarE e fid nm = withtype $ \t -> Typed $ VarE (Sig nm t) (fid e)

conE' :: (SeriType a) => Name -> Typed Exp a
conE' nm = withtype $ \t -> Typed $ ConE (Sig nm t)

conE :: (SeriType a) => Typed Exp a -> Name -> Typed Exp a
conE _ nm = withtype $ \t -> conE' nm

enved :: Typed Exp a -> [Dec] -> Typed (Env Exp) a
enved e x = Typed $ mkenv x (typed e)

-- Make a method
--   The first typed expression is ignored (it's only used to get the right
--   type of the second expression), the second is used for the body of the
--   method.
method :: Name -> Typed Exp a -> Typed Exp a -> Method
method n _ e = Method n (typed e)
