
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}

module Seri.FrontEnd.Declarations.Library (
    SeriDec(..),
    declval', declcon', decltycon', decltyvar', decltype', declinst', declclass', declvartinst',
    ) where

import Data.List(nub)
import Language.Haskell.TH

import Seri.Utils.TH
import qualified Seri.Lambda.IR as S
import qualified Seri.FrontEnd.Typed as S
import Seri.FrontEnd.Declarations.Names
import Seri.FrontEnd.Declarations.Utils
import Seri.FrontEnd.Declarations.SeriDec
import Seri.FrontEnd.Declarations.Polymorphic

-- declval' name ty exp
-- Make a seri value declaration
--   name - name of the seri value being defined.
--   ty - the polymorphic haskell type of the expression.
--   exp - the value
--
-- For (contrived) example, given:
--  name: foo
--  ty: (Eq a) => a -> Integer
--  exp: lamE "x" (\x -> appE (varE "incr") (integerE 41))
--  iscon: False
--
-- The following haskell declarations are generated (approximately):
--
-- To specify the proper type of the variable referencing foo in typed
-- construction:
--  _seriP_foo :: (Eq a, SeriType a) => Typed Exp (a -> Integer)
--  _seriP_foo = lamE "x" (\x -> appE (varE "incr") (integerE 41))
--
-- To specify that foo is not a method of a class.
--  _seriI_foo :: Typed Exp (a -> Integer) -> VarInfo
--  _seriI_foo _ = noinst
--
--  data SeriDec_foo = SeriDec_foo
--
--  instance SeriDec SeriDec_foo where
--      dec _ = ValD "foo"
--                  (ForallT ["a"] [Pred "Eq" [VarT_a]] (VarT_a -> Integer))
--                  (typed (_seri_foo :: Typed Exp (VarT_a -> Integer)))
declval' :: Name -> Type -> Exp -> [Dec]
declval' n t e =
  let dt = valuetype t
      sig_P = SigD (valuename n) dt
      impl_P = FunD (valuename n) [Clause [] (NormalB e) []]

      sig_I = SigD (instidname n) (instidtype t)
      impl_I = FunD (instidname n) [Clause [WildP] (NormalB $ ConE 'S.Declared) []]

      exp = apply 'S.typed [SigE (VarE (valuename n)) (concrete dt)]
      body = applyC 'S.ValD [string n, seritypeexp t, exp]
      ddec = seridec (prefixed "D_" n) body

  in [sig_P, impl_P, sig_I, impl_I] ++ ddec

-- declcon' name ty
-- Make a seri data constructor declaration
--   name - name of the seri data constructor being defined.
--   ty - the polymorphic haskell type of the expression.
--
-- For (contrived) example, given:
--  name: Foo
--  ty: a -> Bar
--
-- The following haskell declarations are generated (approximately):
--
-- Used to specify the type of Foo in typed construction.
--  _seriP_Foo :: (SeriType a) => Typed Exp (a -> Bar)
--  _seriP_Foo = conE' "Foo"
declcon' :: Name -> Type -> [Dec]
declcon' n t =
  let dt = valuetype t
      sig_P = SigD (valuename n) dt
      impl_P = FunD (valuename n) [Clause [] (NormalB (apply 'S.conE' [string n])) []]
  in [sig_P, impl_P]


-- decltycon'
--
-- Given the name of a type constructor and its kind, make a SeriType instance
-- for it. 
--
-- To determine the S.Type of a type constructor for use in, among other
-- things, InstD declarations: 
-- _seriS_Foo :: S.Type
-- _seriS_Foo = ...
--
-- To form a concrete value of the given type. This is primarally useful for
-- type constructors of kind greater than *.
-- _seriK_Foo :: Foo ()
-- _seriK_Foo = undefined
--
-- With the Seri type corresponding to this type constructor.
--
-- Use 0 for kind *
--     1 for kind * -> *
--     2 for kind * -> * -> *
--     etc...
decltycon' :: Integer -> Name -> [Dec]
decltycon' k nm =
  let classname = kindsuf k "SeriType"
      methname = kindsuf k "seritype"

      stimpl = FunD (mkName methname) [Clause [WildP] (NormalB (AppE (ConE 'S.ConT) (string nm))) []]
      stinst = InstanceD [] (AppT (ConT (mkName classname)) (ConT nm)) [stimpl]

      body = AppE (ConE 'S.ConT) (string nm)
      sig_S = SigD (tycontypename nm) (ConT ''S.Type)
      impl_S = ValD (VarP (tycontypename nm)) (NormalB body) []

      vars = replicate (fromInteger k) (ConT ''())
      sig_K = SigD (concretevaluename nm) (appts (ConT nm : vars))
      impl_K = ValD (VarP (concretevaluename nm)) (NormalB (VarE 'undefined)) []
  in [stinst, sig_S, impl_S, sig_K, impl_K]

-- decltyvar'
--
-- Given the name of a type variable and its kind, make a SeriType instance
-- for it and other relevant things, just like decltycon' does for type
-- constructors.
decltyvar' :: String -> [Dec]
decltyvar' vn =  
 let nm = (mkName $ "VarT_" ++ vn)
     k = tvnamekind vn
     dataD = DataD [] nm (map (\n -> PlainTV (mkName [n])) (take (fromInteger k) "abcd")) [NormalC nm []] []

     classname = kindsuf k "SeriType"
     methname = kindsuf k "seritype"

     polytype = (concrete (VarT (mkName vn)))

     body = (AppE (ConE 'S.VarT) (string (mkName vn)))
     stimpl = FunD (mkName methname) [Clause [WildP] (NormalB body ) []]
     stinst = InstanceD [] (AppT (ConT (mkName classname)) polytype) [stimpl]

     sig_S = SigD (tycontypename nm) (ConT ''S.Type)
     impl_S = ValD (VarP (tycontypename nm)) (NormalB body) []

     vars = replicate (fromInteger k) (ConT ''())
     sig_K = SigD (concretevaluename nm) (appts (polytype : vars))
     impl_K = ValD (VarP (concretevaluename nm)) (NormalB (VarE 'undefined)) []
  in [dataD, stinst, sig_S, impl_S, sig_K, impl_K]

-- decltype' 
-- Given a type declaration, make a seri type declaration for it, assuming the
-- type is already defined in haskell.
--
-- For example, given 
--    data Foo a = Bar Integer
--               | Sludge a
--
-- The following haskell declarations are generated:
--    instance SeriType1 Foo where
--       seritype1 _ = ConT "Foo"
--
--    data SeriDecD_Foo = SeriDecD_Foo
--
--    instance SeriDec SeriDecD_Foo where
--        dec _ = DataD "Foo" ["a"] [Con "Bar" [ConT "Integer"],
--                                   Con "Sludge" [ConT "VarT_a"]]
--
--    _seriP_Bar :: Typed Exp (Integer -> Foo)
--    _seriP_Bar = conE "Bar"
--
--    _seriP_Sludge :: (SeriType a) => Typed Exp (a -> Foo)
--    _seriP_Sludge = conE "Sludge"
--
-- Record type constructors are also supported, in which case the selector
-- functions will also be declared like normal seri values.
--
decltype' :: Dec -> [Dec]
decltype' (DataD [] dt vars cs _) =
 let vnames = map tyvarname vars
     dtapp = appts $ (ConT dt):(map VarT vnames)

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
     -- Note: RecC is not canonical, so we assume we needn't deal with it
     -- here.
     mkcon :: Con -> [Dec]
     mkcon (NormalC nc sts) = declcon' nc (contype $ map snd sts)

     -- Given a constructor, return an expression corresponding to the Seri
     -- Con representing that constructor.
     mkconinfo :: Con -> Exp
     mkconinfo (NormalC n sts) = applyC 'S.Con [string n, ListE (map (\(_, t) -> seritypeexp t) sts)]

     body = applyC 'S.DataD [string dt, ListE (map string vnames), ListE (map mkconinfo cs)]
     ddec = seridec (prefixed "D_" dt) body

     constrs = concat $ map mkcon cs

     stinst = decltycon' (toInteger $ length vars) dt
 in stinst ++ ddec ++ constrs


-- declclass
-- Make a seri class declaration.
--
-- For example, given the class:
--   class Foo a where
--      foo :: a -> Integer
--
-- We generate:
--   class (SeriType a) => SeriClass_Foo a where
--     _seriP_foo :: Typed Exp (a -> Integer)
--     _seriI_foo :: Typed Exp (a -> Integer) -> VarInfo
--   
-- To figure out the specific type of a method when declaring an instance of
-- this class:
--   _seriT_foo :: a -> Typed Exp (a -> Integer)
--   _seriT_foo = undefined
-- 
--   data SeriDecC_Foo = SeriDecC_Foo
--   instance SeriDec SeriDecC_Foo where
--     dec = ClassD "Foo" ["a"] [Sig "foo" (VarT_a -> Integer)]
declclass' :: Dec -> [Dec]
declclass' (ClassD [] nm vars [] sigs) =
  let gett t = case t of
                 ForallT _ _ t' -> t'
                 _ -> t

      mksig :: Dec -> [Dec]
      mksig (SigD n ft) =
        let t = gett ft
            sig_P = SigD (valuename n) (valuetype t)
            sig_I = SigD (instidname n) (instidtype t)
        in [sig_P, sig_I]

      ctx = map stpred vars
      class_D = ClassD ctx (classname nm) vars [] (concat $ map mksig sigs)

      mkt :: Dec -> [Dec]
      mkt (SigD n ft) = 
        let t = gett ft

            vararg :: TyVarBndr -> Type
            vararg v = appts $ [VarT (tyvarname v)] ++ replicate (fromInteger $ tvarkind v) (ConT $ mkName "()")

            ty = arrowts $ map vararg vars ++ [texpify (concrete' (map tyvarname vars) t)]
            sig_T = SigD (methodtypename n) (ForallT vars [] ty)
            impl_T = FunD (methodtypename n) [Clause [WildP] (NormalB (VarE 'undefined)) []]
        in [sig_T, impl_T]

      type_ds = concat $ map mkt sigs

      mkdsig :: Dec -> Exp
      mkdsig (SigD n ft) = applyC 'S.Sig [string n, seritypeexp (gett ft)]

      tyvars = ListE $ map (string . tyvarname) vars
      dsigs = ListE $ map mkdsig sigs
      body = applyC 'S.ClassD [string nm, tyvars, dsigs]
      ddec = seridec (prefixed "C_" nm) body
      
  in [class_D] ++ type_ds ++ ddec


-- declinst
-- Make a seri instance declaration.
--
-- For example, given the instance
--   instance Foo Bool where
--      foo _ = 2
--
-- Generates:
--   instance SeriClass_Foo Bool where
--     _seriP_foo = ...
--     _seriI_foo _ = Inst "Foo" [Bool]

--   data SeriDecI_Foo$Bool = SeriDecI_Foo$Bool
--   instance SeriDec SeriDecI_Foo$Bool where
--     dec = InstD "Foo" [Bool] [
--             method "foo" (_seriT_foo _seriK_Bool) (...)
--             ]
--  
declinst'' :: Bool -> Dec -> [Dec]
declinst'' addseridec i@(InstanceD [] tf impls) =
  let unapp :: Type -> [Type]
      unapp (AppT a b) = unapp a ++ [b]
      unapp t = [t]
    
      ((ConT cn):ts) = unapp tf

      iname = string cn
      itys = ListE $ map seritypeexp ts

      mkimpl :: Dec -> [Dec]
      mkimpl (ValD (VarP n) (NormalB b) []) =
        let p = ValD (VarP (valuename n)) (NormalB b) []
            i = FunD (instidname n) [Clause [WildP] (NormalB (applyC 'S.Instance [iname, itys])) []]
        in [p, i]

      idize :: Type -> String
      idize (AppT a b) = idize a ++ "$" ++ idize b
      idize (ConT nm) = nameBase nm

      impls' = concat $ map mkimpl impls
      inst_D = InstanceD [] (appts $ (ConT (classname cn)):ts) impls'

      concretevals = map (\(ConT tnm) -> VarE (concretevaluename tnm)) ts
      mkmeth (ValD (VarP n) (NormalB b) _) = 
        apply 'S.method [string n, apply (methodtypename n) concretevals, b]

      methods = ListE $ map mkmeth impls
      body = applyC 'S.InstD [iname, itys, methods]
      ddec = seridec (mkName $ "I_" ++ (idize tf)) body
   in [inst_D] ++ if addseridec then ddec else []
declinst'' _ i = error $ "TODO: declinst " ++ show i

declinst' :: Dec -> [Dec]
declinst' = declinst'' True

-- Given the declaration of a SeriClass and a list of type variable
-- parameters, generate a dummy instance for that class.
declvartinst' :: Dec -> [S.Name] -> [Dec]
declvartinst' (ClassD _ n _ _ sigs) vs =
  let mkimpl :: String -> Dec
      mkimpl n = ValD (VarP (mkName n)) (NormalB (VarE 'undefined)) []

      -- TODO: this assumes the prefixes for all the methods in the SeriClass
      -- corresponding to the same method in the original class are of the
      -- same length. That seems... bad to do.
      prefixlen = length $ nameBase (valuename (mkName ""))
      names = nub $ map (\(SigD n _) -> drop prefixlen (nameBase n)) sigs
      inst = InstanceD [] (appts $ (ConT (declassname n)):(map (\v -> ConT $ mkName ("VarT_" ++ v)) vs)) (map mkimpl names)
  in declinst'' False inst 
