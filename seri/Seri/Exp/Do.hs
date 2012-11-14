
module Seri.Exp.Do (
    Stmt(..), doE,
    ) where

import Seri.Type
import Seri.Name
import Seri.Sig
import Seri.Fresh
import Seri.Exp.Exp
import Seri.Exp.Match
import Seri.Exp.Sugar

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
  in mletE p e rest
doE ((NoBindS e):stmts) =
  let rest = doE stmts
      tbind = (arrowsT [typeof e, typeof rest, typeof rest])
  in appsE (varE (Sig (name ">>") tbind)) [e, rest]
doE ((BindS p e):stmts) =
  let rest = doE stmts
      f = mlamE $ MMatch [p] rest
      tbind = (arrowsT [typeof e, typeof f, typeof rest])
  in appsE (varE (Sig (name ">>=") tbind)) [e, f]

