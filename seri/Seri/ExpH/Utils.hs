
{-# LANGUAGE PatternGuards #-}

module Seri.ExpH.Utils (
    transform,
    runio, caseEH, ifEH,
    ) where

import Data.Maybe

import Seri.Type
import Seri.Name
import Seri.Sig
import Seri.Ppr
import Seri.ExpH.Ppr
import Seri.ExpH.ExpH
import Seri.ExpH.Sugar


instance Assign ExpH where
   assignl f e =
    let me = assignl f 
        mt = assignl f
    in case e of
         LitEH {} -> e
         ConEH n t xs -> ConEH n (mt t) (map me xs)
         VarEH (Sig n t) -> VarEH (Sig n (mt t))
         AppEH a b -> AppEH (me a) (me b)
         LamEH (Sig n t) b -> LamEH (Sig n (mt t)) $ \x -> (me (b x))
         CaseEH x (Sig kn kt) y n -> CaseEH (me x) (Sig kn (mt kt)) (me y) (me n)
         ErrorEH t m -> ErrorEH (mt t) m

-- Perform a generic transformation on an expression.
-- Applies the given function to each subexpression. Any matching
-- subexpression is replaced with the returned value, otherwise it continues
-- to recurse.
transform :: (ExpH -> Maybe ExpH) -> ExpH -> ExpH
transform g e | Just v <- g e = v
transform g e =
  let me = transform g
  in case e of
       LitEH {} -> e
       ConEH n s xs -> ConEH n s (map me xs)
       VarEH {} -> e 
       PrimEH _ _ f xs -> f (map me xs)
       AppEH f x -> appEH (me f) (me x)
       LamEH s f -> lamEH s $ \x -> me (f x)
       CaseEH x k y d -> caseEH (me x) k (me y) (me d)
       ErrorEH {} -> e

-- | Given a Seri expression of type IO a,
-- returns the Seri expression of type a which results from running the IO
-- computation.
runio :: ExpH -> IO ExpH
runio e
 | Just (_, msg) <- de_errorEH e = error $ "seri: " ++ msg
 | Just io <- de_ioEH e = io
 | otherwise = error $ "runio got non-IO: " ++ pretty (un_letEH e)

caseEH :: ExpH -> Sig -> ExpH -> ExpH -> ExpH
caseEH x k@(Sig nk _) y n
 | Just (s, _, vs) <- de_conEH x
    = if s == nk then appsEH y vs else n
 | Just (_, msg) <- de_errorEH x = errorEH (typeof n) msg
 | otherwise = CaseEH x k y n

ifEH :: ExpH -> ExpH -> ExpH -> ExpH
ifEH p a b = caseEH p (Sig (name "True") boolT) a b

