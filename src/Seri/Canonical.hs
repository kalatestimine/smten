
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}

module Seri.Canonical (
    Canonical(..)
    ) where

import Language.Haskell.TH
import Seri.Slice

-- Canonical
--  Given a TH declaration or expression, reduce it to a canonical form
--  directly expressable in Seri.
--
--  See the source code below for what all is canonicalized.
--  TODO: is there a better way to document what is considered canonical?
class Canonical a where
    canonical :: a -> a

instance Canonical Exp where
    -- Special case, don't canonicalize slices
    canonical e | sliceof e /= Nothing = e

    canonical e@(VarE {}) = e
    canonical e@(ConE {}) = e
    canonical e@(LitE {}) = e
    
    canonical (AppE a b) = AppE (canonical a) (canonical b)

    -- De-infixation
    canonical (InfixE (Just a) op (Just b)) = canonical $ AppE (AppE op a) b

    canonical (LamE ps@[VarP x] a) = LamE ps (canonical a)

    -- We convert lambda expressions with multiple arguments, such as
    --  \a b -> blah
    -- To nested lambda expressions of single arguments:
    --  \a -> (\b -> blah)
    canonical (LamE (x:xs@(_:_)) a) = LamE [x] (canonical $ LamE xs a)

    -- We turn a tuple (a, b, ...) of N elements into
    --  (,, ...) a b ...
    canonical (TupE es)
     = let n = length es
           tupn = ConE (mkName $ "(" ++ replicate (n-1) ',' ++ ")")
       in canonical (foldl AppE tupn es)

    canonical (CondE p a b) = CondE (canonical p) (canonical a) (canonical b)
    canonical (CaseE e ms) = CaseE (canonical e) (canonical ms)

    -- Do statements are desugared
    canonical (DoE stmts) =
      let desugar :: [Stmt] -> Exp
          desugar [NoBindS e] = e
          desugar ((NoBindS e):stmts)
              = AppE (AppE (VarE $ mkName ">>") e) (desugar stmts)
          desugar ((BindS p e):stmts)
              = AppE (AppE (VarE $ mkName ">>=") e) (LamE [p] (desugar stmts))
      in canonical $ desugar stmts

    -- We turn a list literal [a, b, ...] into its construction:
    --  a:b:...:[]
    canonical (ListE es)
     = let desugar :: [Exp] -> Exp
           desugar [] = ConE ''[]
           desugar (x:xs) = InfixE (Just x) (ConE $ mkName ":") (Just (desugar xs))
       in canonical $ desugar es

    canonical (SigE e t) = SigE (canonical e) t
    canonical e = error $ "TODO: canonical " ++ show e

instance Canonical Pat where
    canonical p@(LitP {}) = p
    canonical p@(VarP {}) = p

    -- Turn a tuple pattern (a, b, ...) into constructor form
    --      (,,...) a b ...
    canonical (TupP ps) =
      let n = length ps
          tupn = mkName $ "(" ++ replicate (n-1) ',' ++ ")"
      in canonical $ ConP tupn ps

    canonical (ConP n ps) = ConP n (canonical ps)

    -- De-infixation of patterns
    canonical (InfixP a nm b) = canonical (ConP nm [a, b])

    canonical p@(WildP) = p

    -- Turn a list pattern [a, b, ...] into constructor for
    --      a:b:...:[]
    canonical (ListP []) = canonical $ ConP (mkName "[]") []
    canonical (ListP (x:xs)) = canonical $ ConP (mkName ":") [x, ListP xs]

    canonical p = error $ "TODO: canonical " ++ show p

instance Canonical Dec where
    -- Reduce multiple function clauses to a single expression
    --
    -- Each clause of the form: a b c ... = foo is turned into a case match
    -- of the form: (a, b, c, ...) -> foo.
    --
    -- For this to work, all clauses must have the same number of argument
    -- patterns. We can't yet handle the case where different clauses of the
    -- same function take a different number of arguments. (though it
    -- wouldn't be too difficult to handle that case).
    canonical (FunD nm clauses) =
      let Clause pats1 _ _ = head clauses
          nargs = length pats1
     
          mkmatch :: Clause -> Match
          mkmatch (Clause pats _ _) | nargs /= length pats
            = error $ "Not all clauses of the function " ++ show nm ++
                      " have the same number of arguments. " ++
                      "This is not yet supported"
          mkmatch (Clause pats body decls) =
             if nargs == 1
                then Match (head pats) body decls
                else Match (TupP pats) body decls
     
          -- TODO: hopefully these argnames don't shadow any thing they shouldn't.
          argnames = [mkName $ "_" ++ show i | i <- [1..nargs]]
          casearg = if nargs == 1 then VarE (head argnames) else TupE (map VarE argnames)
          body = LamE (map VarP argnames) $ CaseE casearg (map mkmatch clauses)
       in canonical $ ValD (VarP nm) (NormalB body) []

    canonical (ValD p b ds) = ValD (canonical p) (canonical b) (canonical ds)

    canonical d@(DataD {}) = d
    canonical d@(SigD {}) = d
    canonical (InstanceD c t ds) = InstanceD c t (canonical ds)

    canonical d = error $ "TODO: canonical " ++ show d

instance (Canonical a) => Canonical [a] where
    canonical = map canonical

instance Canonical Body where
    canonical (NormalB e) = NormalB (canonical e)
    canonical b = error $ "TODO: canonical " ++ show b

instance Canonical Match where
    canonical (Match p b ds) = Match (canonical p) (canonical b) (canonical ds)

