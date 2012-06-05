
module Seri.Lambda.Parser.Type (typeT) where

import Text.Parsec hiding (token)

import Seri.Lambda.IR
import Seri.Lambda.Parser.Utils

typeT :: Parser Type
typeT = forallT <|> appsT

forallT :: Parser Type
forallT = do
    token "forall"
    tvars <- many vname
    token "."
    ctx <- option [] contextT
    t <- typeT
    return (ForallT tvars ctx t)

contextT :: Parser [Pred]
contextT = do
    token "("
    p <- predicateT
    ps <- many (token "," >> predicateT)
    token ")"
    token "=>"
    return (p:ps)

predicateT :: Parser Pred
predicateT = do
    n <- cname
    ts <- many typeT
    return (Pred n ts)

appsT :: Parser Type
appsT = atomT `chainl1` appT

appT :: Parser (Type -> Type -> Type)
appT = return AppT

atomT :: Parser Type
atomT = parenT <|> conT <|> varT

parenT :: Parser Type
parenT = do
    token "("
    x <- typeT
    token ")"
    return x

conT :: Parser Type
conT = do
    n <- cname
    return (ConT n)

varT :: Parser Type
varT = do
    n <- vname
    return (VarT n)
