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

-- | Target for elaborating seri expressions.
module Seri.Elaborate.Elaborate (
    elaborate,
    ) where

import Debug.Trace

import Data.Bits
import Data.Functor
import Data.List(genericLength)
import Data.Maybe(fromMaybe)
import Data.Monoid

import Seri.Bit
import Seri.Failable
import qualified Seri.HashTable as HT
import Seri.Name
import Seri.Lit
import Seri.Sig
import Seri.Type
import Seri.Exp
import Seri.ExpH
import Seri.Dec
import Seri.Ppr (pretty)

import Seri.Elaborate.ExpH

-- | Elaborate an expression in ExpH form.
elaborate :: ExpH -> ExpH
elaborate =
  let -- elaborate the given expression
      elab :: ExpH -> ExpH
      elab e =
        case e of
          LitEH l -> e
          ConEH s -> e
          VarEH s -> e
          PrimEH _ f xs -> f (map elab xs)
          AppEH ES_Done _ _ -> e
          AppEH _ f arg -> 
             case (elab f, elab arg) of
               (CaseEH _ a k y n, arg) ->
                 let -- Perform argument pushing.
                     -- (case a of
                     --     k -> y
                     --     _ -> n) arg
                     -- Where y = \v1 -> \v2 -> ... -> yv
                     -- Translates to:
                     --     case a of
                     --         k -> \v1 -> \v2 -> ... -> yv arg
                     --         _ -> n arg
                     yify :: Integer -> (ExpH -> ExpH) -> ExpH -> ExpH
                     yify 0 f x = f x
                     yify n f (LamEH _ s b) = LamEH ES_None s $ \x ->
                         (yify (n-1) f (b x))
                     yify n f x = error $ "yify got: " ++ pretty x

                     kargs = genericLength (de_arrowsT (typeof k)) - 1

                     lam = LamEH ES_None (Sig (name "_z") (typeof arg)) $ \av ->
                        let ybody = \yv -> AppEH ES_None yv av
                            y' = yify kargs ybody y
                            n' = AppEH ES_None n av
                        in CaseEH ES_None a k y' n'
                 in elab $ AppEH ES_None lam arg
               (LamEH _ _ b, arg) -> b arg
               (f', arg) -> AppEH ES_Done f' arg
          LamEH ES_Done _ _ -> e
          LamEH _ v f -> LamEH ES_Done v (\x -> elab (f x))
          CaseEH ES_Done _ _ _ _ -> e
          CaseEH _ arg k y n ->
            case (elab arg, k, elab y, elab n) of
                (arg, Sig nk _, _, no) | (ConEH (Sig s _), vs) <- de_appsEH arg ->
                    if s == nk
                        then elab $ appsEH y vs
                        else no
                (arg, k1, _, _)
                    | CaseEH _ x2 k2 y2 n2 <- arg ->
                        let -- Decasify:
                            --  case (case x2 of k2 -> y2 ; _ -> n2) of
                            --      k1 -> y;
                            --      _ -> n1;
                            --
                            --  Where: y2 = \v1 -> \v2 -> ... -> y2v
                            --
                            -- Turns into:
                            --  case x2 of
                            --     k2 -> \v1 -> \v2  -> ... ->
                            --                case y2v of
                            --                    k1 -> y;
                            --                    _ -> n;
                            --     _ -> case n2 of
                            --            k1 -> y;
                            --            _ -> n;
                            -- TODO: use lets to maintain sharing of y and n.
                            y2ify :: Integer -> (ExpH -> ExpH) -> ExpH -> ExpH
                            y2ify 0 f x = f x
                            y2ify n f (LamEH _ s b) = LamEH ES_None s $ \x ->
                                (y2ify (n-1) f (b x))
                            y2ify n f x = error $ "y2ify got: " ++ pretty x

                            k2args = genericLength (de_arrowsT (typeof k2)) - 1

                            y2body = \x -> CaseEH ES_None x k1 y n
                            y2' = y2ify k2args y2body y2
                            n2' = CaseEH ES_None n2 k1 y n
                        in elab $ CaseEH ES_None x2 k2 y2' n2' 
                (arg@(VarEH (Sig nm t)), k, _, _) | t == boolT ->
                    let Just v = de_boolEH (ConEH k)
                    in CaseEH ES_Done arg k (elab (concretize nm v y)) (elab (concretize nm (not v) n))
                (arg, k, yes, no) -> CaseEH ES_Done arg k yes no
        
  in elab

-- Replace all occurences of the boolean variable with given name to the value
-- True or False in the given expression.
concretize :: Name -> Bool -> ExpH -> ExpH
concretize n v
 = let g :: ExpH -> Maybe ExpH
       g (VarEH (Sig nm _)) | n == nm = Just (boolEH v)
       g _ = Nothing
   in Seri.ExpH.transform g

