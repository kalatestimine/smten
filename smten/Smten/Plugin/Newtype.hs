
module Smten.Plugin.Newtype (
    newtypeCG,
  ) where

import GhcPlugins

import Data.Functor

import Smten.Plugin.CG
import Smten.Plugin.Name
import Smten.Plugin.Type
import qualified Smten.Plugin.Output.Syntax as S


newtypeCG :: TyCon -> DataCon -> CG [S.Dec]
newtypeCG t constr = do
    let n = tyConName t
        tyvars = tyConTyVars t
    ntD <- newtypeD t constr
    conD <- conD n
    shsD <- smtenHS n tyvars constr
    return $ concat [ntD, conD, shsD]

-- newtype Foo a b ... = Foo {
--   deFoo :: ...
-- }
newtypeD :: TyCon -> DataCon -> CG [S.Dec]
newtypeD t constr = do
    let mkcon :: DataCon -> CG S.Con
        mkcon d = do
          nm <- nameCG (dataConName d)
          fnm <- denewtynmCG (dataConName d)
          [ty] <- mapM typeCG (dataConOrigArgTys d)
          return $ S.RecC nm [S.RecField fnm ty]

    nm' <- nameCG (tyConName t)
    vs <- mapM (qnameCG . varName) (tyConTyVars t)
    k <- mkcon constr
    return [S.NewTypeD nm' vs k]

-- __Foo = Foo
conD :: Name -> CG [S.Dec]
conD n = do
  nm <- nameCG n
  cnm <- connmCG n
  return [S.ValD $ S.Val cnm Nothing (S.VarE nm)]
  
-- Note: we currently don't support crazy kinded instances of SmtenHS. This
-- means we are limited to "linear" kinds of the form (* -> * -> ... -> *)
--
-- To handle that properly, we chop off as many type variables as needed to
-- get to a linear kind.
--   call the chopped off type variables c1, c2, ...
--
-- instance (SmtenN c1, SmtenN c2, ...) => SmtenHSN (Foo c1 c2 ...) where
--   iteN = ...
--   ...
smtenHS :: Name -> [TyVar] -> DataCon -> CG [S.Dec]
smtenHS nm tyvs constr = do
   let (rkept, rdropped) = span (isStarKind . tyVarKind) (reverse tyvs)
       n = length rkept
       dropped = reverse rdropped
   tyvs' <- mapM tyvarCG dropped
   qtyname <- qtynameCG nm
   ctx <- concat <$> mapM ctxCG dropped
   smtenhsnm <- usequalified "Smten.Runtime.SmtenHS" ("SmtenHS" ++ show n)
   let ty = S.ConAppT smtenhsnm [S.ConAppT qtyname tyvs']
       cn = dataConName constr
   ite <- iteD cn n
   unreach <- unreachableD cn n
   traces <- traceD cn n
   return [S.InstD ctx ty [ite, unreach, traces]]

-- iteN = \p a b -> iteS p a b (Foo (ite0 p (__deNewTyFoo a) (__deNewTyFoo b)))
iteD :: Name -> Int -> CG S.Method
iteD nm k = do
  ite0nm <- usequalified "Smten.Runtime.SmtenHS" "ite0"
  iteS <- S.VarE <$> usequalified "Smten.Runtime.Formula.BoolF" "iteS"
  cn <- qnameCG nm
  dcn <- qdenewtynmCG nm
  let ite = foldl1 S.AppE [
        S.VarE ite0nm,
        S.VarE "p",
        S.AppE (S.VarE dcn) (S.VarE "a"),
        S.AppE (S.VarE dcn) (S.VarE "b")]
      foo = S.AppE (S.VarE cn) ite
      ited = S.appsE iteS [S.VarE "p", S.VarE "a", S.VarE "b", foo]
      body = S.LamE "p" (S.LamE "a" (S.LamE "b" ited))
  return $ S.Method ("ite" ++ show k) body

-- unreachableN = Foo unreachable
unreachableD :: Name -> Int -> CG S.Method
unreachableD nm k = do
  xx <- S.VarE <$> usequalified "Smten.Runtime.SmtenHS" "unreachable"
  c <- S.VarE <$> qnameCG nm
  return $ S.Method ("unreachable" ++ show k) (S.AppE c xx)

-- traceSN = \x -> traceSNT "Foo" (traceS0 (__deNewTyFoo x))
traceD :: Name -> Int -> CG S.Method
traceD nm k = do
  trc <- S.VarE <$> usequalified "Smten.Runtime.SmtenHS" "traceS0"
  trcnt <- S.VarE <$> usequalified "Smten.Runtime.Trace" "traceSNT"
  dcn <- S.VarE <$> qdenewtynmCG nm
  let cnm = S.LitE (S.StringL (occNameString $ nameOccName nm))
      body = S.AppE (S.AppE trcnt cnm) (S.AppE trc (S.AppE dcn (S.VarE "x")))
  return $ S.Method ("traceS" ++ show k) (S.LamE "x" body)

