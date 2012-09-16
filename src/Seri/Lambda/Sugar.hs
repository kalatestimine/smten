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

-- | Constructor functions for desugaring higher level constructs into the
-- core Seri IR.
module Seri.Lambda.Sugar (
    caseE, deCaseE, trueP, falseP, ifE, deIfE, lamE, deLamE, letE, deLetE,
    Stmt(..), doE,
    ConRec(..), recordD, recordC, recordU,
    --deriveEq,
    ) where

import Control.Monad
import Data.List((\\))

import Seri.Failable
import Seri.Lambda.IR
import Seri.Lambda.Prelude
import Seri.Lambda.Types
import Seri.Lambda.Utils

-- | case x of
--      p1 -> e1;
--      p2 -> e2;
--      ...
caseE :: Exp -> [Match] -> Exp
caseE x ms = AppE (LaceE ms) [x]

deCaseE :: Exp -> Maybe (Exp, [Match])
deCaseE (AppE (LaceE ms) [x]) = Just (x, ms)
deCaseE _ = Nothing


trueP :: Pat
trueP = ConP (ConT (name "Bool")) (name "True") []

falseP :: Pat
falseP = ConP (ConT (name "Bool")) (name "False") []

-- | if p then a else b
ifE :: Exp -> Exp -> Exp -> Exp
ifE p a b = caseE p [Match [trueP] a, Match [falseP] b]

deIfE :: Exp -> Maybe (Exp, Exp, Exp)
deIfE e = do
  (p, [Match [t] a, Match [f] b]) <- deCaseE e
  guard $ t == trueP
  guard $ f == falseP
  return (p, a, b)

-- | \a b ... c -> e
lamE :: Match -> Exp
lamE m = LaceE [m]

deLamE :: Exp -> Maybe Match
deLamE (LaceE [m]) = Just m
deLamE _ = Nothing

-- |
-- > let n1 = e1
-- >     n2 = e2
-- >     ...
-- > in e
--
-- TODO: use lazy pattern matching instead of strict?
letE :: [(Pat, Exp)] -> Exp -> Exp
letE [] x = x
letE ((p, e):bs) x = AppE (lamE $ Match [p] (letE bs x)) [e]

unLetE :: Exp -> ([(Pat, Exp)], Exp)
unLetE (AppE f [e]) | Just (Match [p] rest) <- deLamE f
                    , let (bs, x) = unLetE rest
                    = ((p, e):bs, x)
unLetE x = ([], x)

deLetE :: Exp -> Maybe ([(Pat, Exp)], Exp)
deLetE e = case unLetE e of
            ([], _) -> Nothing
            x -> return x

data Stmt = 
    BindS Pat Exp   -- ^ n <- e
  | NoBindS Exp     -- ^ e
  | LetS Pat Exp    -- ^ let p = e
    deriving(Eq, Show)

-- | do { stmts }
-- The final statement of the 'do' must be a NoBindS.
doE :: [Stmt] -> Exp
doE [] = error $ "doE on empty list"
doE [NoBindS e] = e 
doE ((LetS p e):stmts) =
    let rest = doE stmts
    in letE [(p, e)] rest
doE ((NoBindS e):stmts) =
    let rest = doE stmts
        tbind = (arrowsT [typeof e, typeof rest, typeof rest])
    in appsE [VarE (Sig (name ">>") tbind), e, rest]
doE ((BindS p e):stmts) =
    let rest = doE stmts
        f = lamE $ Match [p] rest
        tbind = (arrowsT [typeof e, typeof f, typeof rest])
    in appsE [VarE (Sig (name ">>=") tbind), e, f]
    
-- | Record type constructors.
data ConRec = NormalC Name [Type]
            | RecordC Name [(Name, Type)]
    deriving(Eq, Show)


-- return the undef variable name for a given data constructor name.
record_undefnm :: Name -> Name
record_undefnm n = name "__" `nappend` n `nappend` name "_undef"

-- return the updater for a given field.
record_updnm :: Name -> Name
record_updnm n = name "__" `nappend` n `nappend` name "_update"

-- | Desugar record constructors from a data declaration.
-- Also handles deriving construts.
-- Generates:
--   data declaration with normal constructors.
--   accessor functions for every field.
--   update functions for every field.
--   An undef declaration for each constructor.
recordD :: Name -> [TyVar] -> [ConRec] -> [String] -> [Dec]
recordD nm vars cons derivings =
  let mkcon :: ConRec -> Con
      mkcon (NormalC n ts) = Con n ts
      mkcon (RecordC n ts) = Con n (map snd ts)

      dt = appsT (ConT nm : map tyVarType vars)

      mkundef :: Con -> Dec
      mkundef (Con n ts) =
        let undefnm = (record_undefnm n)
            undefet = arrowsT $ ts ++ [dt]
            undefe = appsE $ ConE (Sig n undefet) : [VarE (Sig (name "undefined") t) | t <- ts]
        in ValD (TopSig undefnm [] dt) undefe

      -- TODO: handle correctly the case where two different constructors
      -- share the same accessor name.
      mkaccs :: ConRec -> [Dec]
      mkaccs (NormalC {}) = []
      mkaccs (RecordC cn ts) = 
        let mkacc :: ((Name, Type), Int) -> Dec
            mkacc ((n, t), i) = 
              let at = arrowsT [dt, t] 
                  pat = ConP dt cn ([WildP pt | (_, pt) <- take i ts]
                         ++ [VarP (Sig (name "x") t)]
                         ++ [WildP pt | (_, pt) <- drop (i+1) ts])
                  body = lamE $ Match [pat] (VarE (Sig (name "x") t))
              in ValD (TopSig n [] at) body
        in map mkacc (zip ts [0..])

      mkupds :: ConRec -> [Dec]
      mkupds (NormalC {}) = []
      mkupds (RecordC cn ts) = 
        let ct = arrowsT $ (map snd ts) ++ [dt]
            mkupd :: ((Name, Type), Int) -> Dec
            mkupd ((n, t), i) =
              let ut = arrowsT [t, dt, dt]
                  mypat = ConP dt cn (
                            [VarP (Sig nm t) | (nm, t) <- take i ts]
                            ++ [WildP t]
                            ++ [VarP (Sig nm t) | (nm, t) <- drop (i+1) ts])
                  myexp = appsE $ ConE (Sig cn ct) : [VarE (Sig n t) | (n, t) <- ts]
                  body = lamE $ Match [VarP (Sig n t), mypat] myexp
              in ValD (TopSig (record_updnm n) [] ut) body
        in map mkupd (zip ts [0..])
                            
      cons' = map mkcon cons
      undefs = map mkundef cons'
      accs = concatMap mkaccs cons
      upds = concatMap mkupds cons
      derivations = [derive d nm vars cons' | d <- derivings]
  in concat [[DataD nm vars cons'], derivations, undefs, accs, upds]

-- | Desugar labelled update.
recordU :: Exp -> [(Name, Exp)] -> Exp
recordU e [] = e
recordU e ((n, v):us) = 
  appsE [VarE (Sig (record_updnm n) (arrowsT [typeof v, typeof e])),
         v, recordU e us]

-- | Desugar labelled constructors.
recordC :: Sig -> [(Name, Exp)] -> Exp
recordC (Sig cn ct) fields = recordU (VarE (Sig (record_undefnm cn) ct)) fields

-- Derive an instance of Eq (before flattening and inference) for the given
-- data type declaration.
deriveEq :: Name -> [TyVar] -> [Con] -> Dec
deriveEq dn vars cs = 
  let dt = appsT (ConT dn : map tyVarType vars)
      mkcon :: Con -> Match
      mkcon (Con cn ts) = 
        let fields1 = [Sig (name $ [c, '1']) t | (t, c) <- zip ts "abcdefghijklmnopqrstuvwxyz"]
            fields2 = [Sig (name $ [c, '2']) t | (t, c) <- zip ts "abcdefghijklmnopqrstuvwxyz"]
            p1 = ConP dt cn [VarP s | s <- fields1]
            p2 = ConP dt cn [VarP s | s <- fields2]
            body = AppE (VarE (Sig (name "and") UnknownT))
                        [listE [appsE [VarE (Sig (name "==") UnknownT), VarE a, VarE b] | (a, b) <- zip fields1 fields2]]
        in Match [p1, p2] body

      def = Match [WildP UnknownT, WildP UnknownT] falseE
      ctx = [Class (name "Eq") [tyVarType c] | c <- vars]
      eqclauses = map mkcon cs ++ [def]
      eq = Method (name "==") (LaceE eqclauses)
      ne = Method (name "/=") (VarE (Sig (name "/=#") UnknownT))
  in InstD ctx (Class (name "Eq") [dt]) [eq, ne]

derive :: String -> Name -> [TyVar] -> [Con] -> Dec
derive "Eq" = deriveEq
derive x = error $ "deriving " ++ show x ++ " not supported in seri"

