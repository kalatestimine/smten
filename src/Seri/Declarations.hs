
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}

module Seri.Declarations (
    SeriDec(..),
    name_P, name_D,
    declval', decltype',
    declprim, declval, decltype, declcommit,
    ) where

import Language.Haskell.TH

import Seri.THUtils
import qualified Seri.IR as SIR
import qualified Seri.Typed as S

class SeriDec a where
    dec :: a -> SIR.Dec

name_X :: String -> Name -> Name
name_X pre x = mkName $ pre ++ nameBase x

-- The name of the (possibly) polymorphic function generated.
name_P :: Name -> Name
name_P = name_X "_seriP_"

-- The name of the declaration type
name_D :: Name -> Name
name_D = name_X "SeriDec_"

unname_D :: SIR.Name -> SIR.Name
unname_D x = drop (length "SeriDec_") x

declprim :: SIR.Name -> Q Type -> Q [Dec]
declprim nm ty = declval nm ty [e| S.primitive $(litE (StringL nm)) |]

declval :: String -> Q Type -> Q Exp -> Q [Dec]
declval n qt qe = do
    t <- qt
    e <- qe
    return $ declval' (mkName n) t e

-- declval' name ty exp
-- Make a seri value declaration.
--   name - name of the seri value being defined.
--   ty - the polymorphic haskell type of the expression.
--   exp - the value
--
-- For (contrived) example, given:
--  name: foo
--  ty: (Eq a) => a -> Integer
--  exp: lamE "x" (\x -> appE (varE "incr") (integerE 41))
--
-- The following haskell declarations are generated (approximately):
--  _seri_foo :: (Eq a, SeriType a) => Typed Exp (a -> Integer)
--  _seri_foo = lamE "x" (\x -> appE (varE "incr") (integerE 41))
--
--  data SeriDec_foo = SeriDec_foo
--
--  instance SeriDec SeriDec_foo where
--      dec _ = valD "foo" (_seri_foo :: Typed Exp (VarT_a -> Integer))
declval' :: Name -> Type -> Exp -> [Dec]
declval' n t e =
  let dt = declize t
      sig_P = SigD (name_P n) dt
      impl_P = FunD (name_P n) [Clause [] (NormalB e) []]

      data_D = DataD [] (name_D n) [] [NormalC (name_D n) []] []

      body = apply 'S.valD [string n, SigE (VarE (name_P n)) (concretize dt)]
      impl_D = FunD 'dec [Clause [WildP] (NormalB body) []]
      inst_D = InstanceD [] (AppT (ConT ''SeriDec) (ConT $ name_D n)) [impl_D]
  in [sig_P, impl_P, data_D, inst_D]

-- decltype' 
-- Given a type declaration, make a seri type declaration for it, assuming the
-- type is already defined in haskell.
--
-- The following is generated for the given type.
--  - an instance of SeriType.
--  - _seriP_Foo and friends for each constructor Foo
decltype' :: Dec -> [Dec]
decltype' (DataD [] dt vars cs _) =
 let numvars = length vars
     classname = "SeriType" ++ if numvars == 0 then "" else show numvars
     methname = "seritype" ++ if numvars == 0 then "" else show numvars
     dtapp = appts $ (ConT dt):(map (\(PlainTV n) -> VarT n) vars)

     -- Assuming the data type is polymorphic in type variables a, b, ...
     -- Given type t, return type (forall a b ... . t)
     --
     contextify :: Type -> Type
     contextify t = ForallT vars [] t

     -- contype: given the list of field types [a, b, ...] for a constructor
     -- form the constructor type: a -> b -> ... -> Foo
     contype :: [Type] -> Type
     contype ts = contextify $ arrowts (ts ++ [dtapp])

     -- produce the declarations needed for a given constructor.
     mkcon :: Con -> [Dec]
     mkcon (NormalC nc sts) =
        let e = apply 'S.conE' [string nc]
            ty = contype (map snd sts)
        in declval' nc ty e
     mkcon (RecC nc sts) =
        let e = apply 'S.conE' [string nc]
            ty = contype (map (\(_, _, t) -> t) sts)
            constrs = declval' nc ty e
            numfields = toInteger $ length sts

            mkacc :: Integer -> Name -> Type -> [Dec]
            mkacc i n st =
                let t = contextify $ arrowts [dtapp, st]
                    e = apply 'S.selector [string dt, integer i, integer numfields]
                in declval' n t e

            accessors = concat $ map (\(i, (n, _, t)) -> mkacc i n t) (zip [0..] sts)
        in constrs ++ accessors

     dec = FunD (mkName methname) [Clause [WildP] (NormalB (AppE (ConE 'SIR.ConT) (string dt))) []]
     inst = InstanceD [] (AppT (ConT (mkName classname)) (ConT dt)) [dec]
     cones = concat $ map mkcon cs
 in concat [[inst], cones]

decltype :: Name -> Q [Dec]
decltype nm = do
    TyConI d <- reify nm
    return $ decltype' d

-- Given the raw haskell type corresponding to an expression, return the type
-- of the haskell function representing an expression of that type.
--
-- For example
--  input: (Eq a) => a -> Integer
--  output: (Eq a, SeriType a) => Typed Exp (a -> Integer) 
declize :: Type -> Type
declize ty = 
  let typedexp t = (AppT (AppT (ConT ''S.Typed) (ConT ''SIR.Exp)) t)

      -- Given a type variable, figure out what predicate we should add for it
      -- in the context.
      --
      -- TODO: this is a bad special case hack. Can we come up with a better
      -- way for figuring out the kind of each type variable?
      stcon :: TyVarBndr -> Pred
      stcon (PlainTV x) | 'm' == head (nameBase x)
        = ClassP ''S.SeriType1 [VarT x]
      stcon (PlainTV x) = ClassP ''S.SeriType [VarT x]

  in case ty of
        ForallT vns c t ->
           let ctx = map stcon vns
           in ForallT vns (c ++ ctx) (typedexp t)
        _ -> typedexp ty

-- Given a potentially polymorphic haskell type, convert it to a concrete
-- haskell type which represents the polymorphic seri type.
--
-- In other words, replace all occurences of VarT "foo" with VarT_foo.
concretize :: Type -> Type
concretize (ForallT _ _ t) = concretize t
concretize (VarT nm) = ConT $ mkName ("VarT_" ++ (nameBase nm))
concretize (AppT a b) = AppT (concretize a) (concretize b)
concretize t = t

-- Declarations may not be seen right away. Call this template haskell
-- function to force the declarations to be committed.
--
-- So, for example, to use this you would declare all your seri functions,
-- then below those in the source file call this as a top level template
-- haskell slice, then below that in the source file you can use quoted seri
-- expressions referring to the declarations.
declcommit :: Q [Dec]
declcommit = return []
