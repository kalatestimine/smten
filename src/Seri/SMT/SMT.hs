
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}

-- Seri.SMT
-- 
-- Extensions to Seri which allow you to express and perform SMT queries.
module Seri.SMT.SMT where

import Seri
import Seri.Lib.Prelude


[s|
    data Query a = Query

    data Answer a = Satisfiable a | Unsatisfiable | Unknown
        deriving (Show, Eq)

    data Free a = Free Integer
|]

instance Monad Query where
    return = error $ "Query return"
    (>>=) = error $ "Query >>="


declprim "free" [t| forall a. Query a |]
declprim "realize" [t| forall a. Free a -> a |]
declprim "assert" [t| Bool -> Query () |]
declprim "query" [t| forall a. a -> Query (Answer a) |]
declprim "return" [t| forall a m . (Monad m) => a -> m a |]
declprim ">>" [t| forall a b m . (Monad m) => m a -> m b -> m b |]
declprim ">>=" [t| forall a b m . (Monad m) => m a -> (a -> m b) -> m b |]

runQuery :: Rule -> [Dec] -> Typed Exp (Query a) -> IO (Typed Exp a)
runQuery = error $ "TODO: runQuery"
