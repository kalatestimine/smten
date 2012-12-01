-------------------------------------------------------------------------------
-- Copyright (c) 2012      SRI International, Inc. 
-- All rights reserved.
--
-- This software was developed by SRI International and the University of
-- Cambridge Computer Laboratory under DARPA/AFRL contract (FA8750-10-C-0237)
-- ("CTSRD"), as part of the DARPA CRASH research programme.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
-------------------------------------------------------------------------------
--
-- Authors: 
--   Richard Uhler <ruhler@csail.mit.edu>
-- 
-------------------------------------------------------------------------------

{-# LANGUAGE PatternGuards #-}

-- Back end target which translates seri programs into Haskell. Supports the
-- Query monad and SMT queries.
module Seri.HaskellF.HaskellF (
    haskellf,
    ) where

import Debug.Trace

import Data.Char(isAlphaNum)
import Data.Functor((<$>))
import Data.List(nub, genericLength)
import Data.Maybe(fromJust)

import qualified Language.Haskell.TH.PprLib as H
import qualified Language.Haskell.TH as H
import qualified Language.Haskell.TH.Syntax as H

import Seri.Failable
import Seri.Name
import Seri.Sig
import Seri.Type
import Seri.Lit
import Seri.Exp
import Seri.Dec
import Seri.Ppr

-- TODO: Here we just drop the qualified part of the name.
-- This is a hack, requiring there are no modules which define an entity of
-- the same name (unlikely...). Really we should form a proper haskell name
-- for whatever this name is used for (varid, conid)
hsName :: Name -> H.Name
hsName n =
  let dequalify :: String -> String
      dequalify n = 
        case break (== '.') n of
            (n', []) -> n'
            (_, ".") -> "."
            (_, n') -> dequalify (tail n')
      symify :: String -> String
      symify s = if issymbol s then "(" ++ s ++ ")" else s
  in H.mkName . symify . dequalify . unname $ n

issymbol :: String -> Bool
issymbol ('(':_) = False
issymbol "[]" = False
issymbol (h:_) = not $ isAlphaNum h || h == '_'


hsLit :: Lit -> H.Exp
hsLit l
 | Just i <- de_integerL l = H.LitE (H.IntegerL i)
 | Just c <- de_charL l = H.AppE (H.VarE (H.mkName "S.seriS")) (H.LitE (H.CharL c))

prependnm :: String -> Name -> H.Name
prependnm m n = hsName $ name m `nappend` n

-- Given the name of a data constructor, return the name of the corresponding
-- abstract constructor function.
constrnm :: Name -> H.Name
constrnm = prependnm "__mk"

-- Given the name of a data constructor, return the name of the function for
-- doing a case match against the constructor.
constrcasenm :: Name -> H.Name
constrcasenm n 
 | n == name "()" = constrcasenm $ name "Unit__"
 | Just x <- de_tupleN n = constrcasenm . name $ "Tuple" ++ show x ++ "__"
 | n == name "[]" = constrcasenm $ name "Nil__"
 | n == name ":" = constrcasenm $ name "Cons__"
constrcasenm n = prependnm "__case" n

hsExp :: Exp -> Failable H.Exp
hsExp (LitE l) = return (hsLit l)
hsExp (ConE (Sig n t))
  | n == name "()" = hsExp (ConE (Sig (name "Unit__") t))
  | Just x <- de_tupleN n = hsExp (ConE (Sig (name $ "Tuple" ++ show x ++ "__") t))
  | n == name ":" = hsExp (ConE (Sig (name "Cons__") t))
  | n == name "[]" = hsExp (ConE (Sig (name "Nil__") t))
hsExp (ConE (Sig n _)) = return $ H.VarE (constrnm n)
hsExp (VarE (Sig n t)) | unknowntype t = return $ H.VarE (hsName n)
hsExp (VarE (Sig n t)) = do
    -- Give explicit type signature to make sure there are no type ambiguities
    ht <- hsType t
    return $ H.SigE (H.VarE (hsName n)) ht
hsExp (AppE f x) = do
    f' <- hsExp f
    x' <- hsExp x
    return $ H.AppE f' x'

hsExp (LamE (Sig n _) x) = do
    x' <- hsExp x
    return $ H.LamE [H.VarP (hsName n)] x'

-- case x of
--    K -> y
--    _ -> n
--
-- Translates to:  __caseK x y n
hsExp (CaseE x (Sig kn kt) y n) = do
    [x', y', n'] <- mapM hsExp [x, y, n]
    return $ foldl1 H.AppE [H.VarE (constrcasenm kn), x', y', n']
        
hsType :: Type -> Failable H.Type
hsType (ConT n) | n == name "()" = return $ H.ConT (H.mkName "Unit__")
hsType (ConT n) | Just x <- de_tupleN n
  = return $ H.ConT (H.mkName $ "Tuple" ++ show x ++ "__")
hsType (ConT n) | n == name "[]" = return $ H.ConT (H.mkName "List__")
hsType (ConT n) | n == name "->" = return H.ArrowT
hsType (ConT n) = return $ H.ConT (hsName n)
hsType (AppT a b) = do
    a' <- hsType a
    b' <- hsType b
    return $ H.AppT a' b'
hsType (VarT n) = return $ H.VarT (hsName n)
hsType (NumT (ConNT i)) = return $ hsnt i
hsType (NumT (VarNT n)) = return $ H.VarT (H.mkName (pretty n))
hsType (NumT (AppNT f a b)) = do
    a' <- hsType (NumT a)
    b' <- hsType (NumT b)
    let f' = case f of
                "+" -> H.ConT $ H.mkName "N__PLUS"
                "-" -> H.ConT $ H.mkName "N__MINUS"
                "*" -> H.ConT $ H.mkName "N__TIMES"
                _ -> error $ "hsType TODO: AppNT " ++ f
    return $ H.AppT (H.AppT f' a') b'
hsType t = throw $ "coreH does not apply to type: " ++ pretty t

-- Return the numeric type corresponding to the given integer.
hsnt :: Integer -> H.Type
hsnt 0 = H.ConT (H.mkName "N__0")
hsnt n = H.AppT (H.ConT (H.mkName $ "N__2p" ++ show (n `mod` 2))) (hsnt $ n `div` 2)

hsTopType :: [Name] -> Context -> Type -> Failable H.Type
hsTopType clsvars ctx t = do
    let (nctx, use) = mkContext (flip notElem clsvars) t
    t' <- hsType t
    ctx' <- mapM hsClass ctx
    case nctx ++ ctx' of
        [] -> return t'
        ctx'' -> return $ H.ForallT (map (H.PlainTV . hsName) use) ctx'' t'

hsClass :: Class -> Failable H.Pred
hsClass (Class nm ts) = do
    ts' <- mapM hsType ts
    return $ H.ClassP (hsName nm) ts'
    
hsMethod :: Method -> Failable H.Dec
hsMethod (Method n e) = do
    let hsn = hsName n
    e' <- hsExp e
    return $ H.ValD (H.VarP hsn) (H.NormalB e') []


hsSig :: [Name]     -- ^ List of varTs to ignore, because they belong to the class.
         -> TopSig
         -> Failable H.Dec
hsSig clsvars (TopSig n ctx t) = do
    t' <- hsTopType clsvars ctx t
    return $ H.SigD (hsName n) t'

    
hsDec :: Dec -> Failable [H.Dec]
hsDec (ValD (TopSig n ctx t) e) = do
    t' <- hsTopType [] ctx t
    e' <- hsExp e
    let hsn = hsName n
    let sig = H.SigD hsn t'
    let val = H.FunD hsn [H.Clause [] (H.NormalB e') []]
    return [sig, val]

hsDec (DataD n _ _) | n `elem` [
  name "Bool",
  name "Char",
  name "Integer",
  name "Bit",
  name "[]",
  name "()",
  name "Answer",
  name "Query",
  name "IO"] = return []

hsDec (DataD n _ _) | Just x <- de_tupleN n = hsDec $ tuple (fromIntegral x)

-- data Foo a b ... = FooA FooA1 FooA2 ...
--                  | FooB FooB1 FooB2 ...
--                  ...
--
-- Translates to:
-- newtype Foo a b ... = Foo S.ExpH
--
-- instance S.SymbolicN Foo where
--  boxN = Foo
--  unboxN (Foo x) = x
--
-- And for each constructor FooB:
-- __mkFooB :: FooB1 -> FooB2 -> ... -> Foo
-- __mkFooB = S.conS "FooB"
-- __caseFooB :: Foo -> (FooB1 -> FooB2 -> ... -> a) -> a -> a
-- __caseFooB = S.caseS "FooB"
-- ...
hsDec (DataD n tyvars constrs) =
  let tyvars' = map (H.PlainTV . hsName . tyVarName) tyvars
      con = H.NormalC (hsName n) [(H.NotStrict, H.ConT (H.mkName "S.ExpH"))]
      dataD = H.NewtypeD [] (hsName n) tyvars' con []

      box = H.FunD (boxmeth (genericLength tyvars)) [
                H.Clause [] (H.NormalB (H.ConE (hsName n))) []]
      unbox = H.FunD (unboxmeth (genericLength tyvars)) [
                H.Clause [H.ConP (hsName n) [H.VarP (H.mkName "x")]]
                    (H.NormalB (H.VarE (H.mkName "x"))) []]

      clsname = clssymbolic (genericLength tyvars)
      ty = H.AppT (H.ConT clsname) (H.ConT (hsName n))
      instD = H.InstanceD [] ty [box, unbox]

      body = H.AppE (H.VarE (H.mkName "S.conT"))
                    (H.AppE (H.VarE (H.mkName "S.name"))
                            (H.LitE (H.StringL (unname n))))
      serit = H.FunD (seritmeth (genericLength tyvars)) [
                H.Clause [H.WildP] (H.NormalB body) []]
      clsnamet = clsserit (genericLength tyvars)
      tyt = H.AppT (H.ConT clsnamet) (H.ConT (hsName n))
      instDt = H.InstanceD [] tyt [serit]
      
      
      mkmk :: Name -> [Type] -> [H.Dec]
      mkmk cn tys =
        let dt = appsT (conT n) (map tyVarType tyvars)
            t = arrowsT $ tys ++ [dt]
            ht = surely $ hsTopType [] [] t

            sigD = H.SigD (constrnm cn) ht

            body = H.AppE (H.VarE (H.mkName "S.conS")) (H.LitE (H.StringL (unname cn)))
            funD = H.FunD (constrnm cn) [H.Clause [] (H.NormalB body) []]
         in [sigD, funD]

      mkcase :: Name -> [Type] -> [H.Dec]
      mkcase cn tys = 
        let dt = appsT (conT n) (map tyVarType tyvars)
            z = VarT (name "z")
            t = arrowsT [dt, arrowsT (tys ++ [z]), z, z]
            ht = surely $ hsTopType [] [] t

            sigD = H.SigD (constrcasenm cn) ht

            body = H.AppE (H.VarE (H.mkName "S.caseS")) (H.LitE (H.StringL (unname cn)))
            funD = H.FunD (constrcasenm cn) [H.Clause [] (H.NormalB body) []]
        in [sigD, funD]

      mkconfs :: Con -> [H.Dec]
      mkconfs (Con cn ctys)
        = concat [f cn ctys | f <- [mkmk, mkcase]]

      mkallconfs :: [Con] -> [H.Dec]
      mkallconfs = concatMap mkconfs

  in return $ concat [[dataD, instDt, instD], mkallconfs constrs]

hsDec (ClassD n vars sigs@(TopSig _ _ t:_)) = do
    let vts = map tyVarName vars
        (ctx, use) = mkContext (flip elem vts) t
    sigs' <- mapM (hsSig vts) sigs
    return $ [H.ClassD ctx (hsName n) (map (H.PlainTV . hsName) use) [] sigs']

hsDec (InstD ctx (Class n ts) ms) = do
    let (nctx, _) = mkContext (const True) (appsT (conT n) ts)
    ctx' <- mapM hsClass ctx
    ms' <- mapM hsMethod ms
    ts' <- mapM hsType ts
    let t = foldl H.AppT (H.ConT (hsName n)) ts'
    return [H.InstanceD (nctx ++ ctx') t ms'] 

hsDec (PrimD s@(TopSig n _ _))
 | n == name "Prelude.__prim_add_Integer" = return []
 | n == name "Prelude.__prim_sub_Integer" = return []
 | n == name "Prelude.__prim_mul_Integer" = return []
 | n == name "Prelude.__prim_show_Integer" = return []
 | n == name "Prelude.<" = return []
 | n == name "Prelude.<=" = return []
 | n == name "Prelude.>" = return []
 | n == name "Prelude.__prim_eq_Integer" = return []
 | n == name "Prelude.__prim_eq_Char" = return []
 | n == name "Prelude.valueof" = return []
 | n == name "Prelude.numeric" = return []
 | n == name "Prelude.error" = return []
 | n == name "Seri.Bit.__prim_fromInteger_Bit" = return []
 | n == name "Seri.Bit.__prim_eq_Bit" = return []
 | n == name "Seri.Bit.__prim_add_Bit" = return []
 | n == name "Seri.Bit.__prim_sub_Bit" = return []
 | n == name "Seri.Bit.__prim_mul_Bit" = return []
 | n == name "Seri.Bit.__prim_concat_Bit" = return []
 | n == name "Seri.Bit.__prim_show_Bit" = return []
 | n == name "Seri.Bit.__prim_not_Bit" = return []
 | n == name "Seri.Bit.__prim_or_Bit" = return []
 | n == name "Seri.Bit.__prim_and_Bit" = return []
 | n == name "Seri.Bit.__prim_shl_Bit" = return []
 | n == name "Seri.Bit.__prim_lshr_Bit" = return []
 | n == name "Seri.Bit.__prim_zeroExtend_Bit" = return []
 | n == name "Seri.Bit.__prim_truncate_Bit" = return []
 | n == name "Seri.Bit.__prim_extract_Bit" = return []
 | n == name "Prelude.return_io" = return []
 | n == name "Prelude.bind_io" = return []
 | n == name "Prelude.nobind_io" = return []
 | n == name "Prelude.fail_io" = return []
 | n == name "Prelude.putChar" = return []
 | n == name "Prelude.getContents" = return []
 | n == name "Seri.SMT.SMT.__prim_free" = return []
 | n == name "Seri.SMT.SMT.assert" = return []
 | n == name "Seri.SMT.SMT.query" = return []
 | n == name "Seri.SMT.SMT.queryS" = return []
 | n == name "Seri.SMT.SMT.return_query" = return []
 | n == name "Seri.SMT.SMT.nobind_query" = return []
 | n == name "Seri.SMT.SMT.bind_query" = return []
 | n == name "Seri.SMT.SMT.fail_query" = return []
 | n == name "Seri.SMT.SMT.runYices1" = return []
 | n == name "Seri.SMT.SMT.runYices2" = return []
 | n == name "Seri.SMT.SMT.runSTP" = return []

hsDec d = throw $ "coreH does not apply to dec: " ++ pretty d

-- haskell decs
--  Compile the given declarations to haskell.
haskellf :: [Dec] -> H.Doc
haskellf env =
  let hsHeader :: H.Doc
      hsHeader = H.text "{-# LANGUAGE ExplicitForAll #-}" H.$+$
                 H.text "{-# LANGUAGE MultiParamTypeClasses #-}" H.$+$
                 H.text "{-# LANGUAGE FlexibleInstances #-}" H.$+$
                 H.text "{-# LANGUAGE ScopedTypeVariables #-}" H.$+$
                 H.text "module Main (__main) where" H.$+$
                 H.text "import qualified Prelude" H.$+$
                 H.text "import qualified Seri.HaskellF.Symbolic as S" H.$+$
                 H.text "import qualified Seri.Name as S" H.$+$
                 H.text "import qualified Seri.Type as S" H.$+$
                 H.text "import qualified Seri.ExpH as S" H.$+$
                 H.text "import Seri.HaskellF.Lib.Prelude" H.$+$
                 H.text "import Seri.HaskellF.Lib.SMT" H.$+$
                 H.text "" H.$+$
                 H.text "__main = __main_wrapper main"

      ds = surely $ (concat <$> mapM hsDec env)
  in hsHeader H.$+$ H.ppr ds

unknowntype :: Type -> Bool
unknowntype (ConT {}) = False
unknowntype (AppT a b) = unknowntype a || unknowntype b
unknowntype (VarT {}) = True
unknowntype (NumT (VarNT {})) = True
unknowntype (NumT {}) = False
unknowntype UnknownT = True

harrowsT :: [H.Type] -> H.Type
harrowsT = foldr1 (\a b -> H.AppT (H.AppT H.ArrowT a) b)

-- Tuple declarations renamed.
tuple :: Int -> Dec
tuple i = 
  let nm = name $ "Tuple" ++ show i ++ "__"
      vars = [NormalTV (name [c]) | c <- take i "abcdefghijklmnopqrstuvwxyz"]
  in DataD nm vars [Con nm (map tyVarType vars)]

clssymbolic :: Integer -> H.Name
clssymbolic 0 = H.mkName "S.Symbolic"
clssymbolic n = H.mkName $ "S.Symbolic" ++ show n

boxmeth :: Integer -> H.Name
boxmeth 0 = H.mkName "box"
boxmeth n = H.mkName $ "box" ++ show n

unboxmeth :: Integer -> H.Name
unboxmeth 0 = H.mkName "unbox"
unboxmeth n = H.mkName $ "unbox" ++ show n

clsserit :: Integer -> H.Name
clsserit 0 = H.mkName "S.SeriT"
clsserit n = H.mkName $ "S.SeriT" ++ show n

seritmeth :: Integer -> H.Name
seritmeth 0 = H.mkName "seriT"
seritmeth n = H.mkName $ "seriT" ++ show n

-- Form the context for declarations.
mkContext :: (Name -> Bool) -- ^ which variable types we should care about
              -> Type       -- ^ a sample use of the variable types
              -> ([H.Pred], [Name])  -- ^ generated context and list of names used.
mkContext p t =
  let nvts = filter p $ nvarTs t
      kvts = filter (p . fst) $ kvarTs t
      ntvs = [H.ClassP (clssymbolic 0) [H.VarT (hsName n)] | n <- nvts]
      stvs = [H.ClassP (clssymbolic k) [H.VarT (hsName n)] | (n, k) <- kvts]
  in (concat [ntvs, stvs], nvts ++ map fst kvts)

