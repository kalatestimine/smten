
{-# LANGUAGE TemplateHaskell #-}

module Seri.Arithmetic where

import Seri.Primitives(trueE, falseE)
import Seri.Declarations
import Seri.Elaborate
import Seri.IR
import Seri.Typed

declprim "+" [t| Typed Exp (Integer -> Integer -> Integer) |]
declprim "-" [t| Typed Exp (Integer -> Integer -> Integer) |]
declprim "*" [t| Typed Exp (Integer -> Integer -> Integer) |]
declprim "<" [t| Typed Exp (Integer -> Integer -> Bool) |]
declprim ">" [t| Typed Exp (Integer -> Integer -> Bool) |]

arithR :: Rule
arithR = Rule $ \decls gr e ->
    case e of 
      (AppE _ (AppE _ (PrimE _ "+") (IntegerE a)) (IntegerE b))
        -> Just $ IntegerE (a+b)
      (AppE _ (AppE _ (PrimE _ "-") (IntegerE a)) (IntegerE b))
        -> Just $ IntegerE (a-b)
      (AppE _ (AppE _ (PrimE _ "*") (IntegerE a)) (IntegerE b))
        -> Just $ IntegerE (a*b)
      (AppE _ (AppE _ (PrimE _ "<") (IntegerE a)) (IntegerE b))
        -> Just $ if a < b then trueE else falseE
      (AppE _ (AppE _ (PrimE _ ">") (IntegerE a)) (IntegerE b))
        -> Just $ if a > b then trueE else falseE
      _ -> Nothing

