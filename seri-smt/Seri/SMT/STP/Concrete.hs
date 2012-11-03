
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}

-- | Print SMT syntax to concrete SMTLIB2.0 syntax.
--
-- TODO: this is based on the Yices.Concrete syntax printer. Should they be
-- merged together or otherwise share code?
module Seri.SMT.STP.Concrete (
    concrete, pretty
  ) where

import Control.Monad.State.Strict
import Data.Ratio
import Data.List(genericLength)

import Seri.Strict
import Seri.SMT.Syntax

bigsize :: Integer
bigsize = 80

data SmallSize = Big | Small Integer
    deriving (Eq, Show)

instance Num SmallSize where
    fromInteger i | i < bigsize = Small i
    fromInteger _ = Big

    (+) Big _ = Big
    (+) _ Big = Big
    (+) (Small a) (Small b) = fromInteger (a+b)

    (*) = error $ "(*) SmallSize"
    abs = error $ "abs SmallSize"
    signum = error $ "signum SmallSize"


data CS = CS {
    cs_pretty :: Bool,

    -- We want to clump together into one line anything that fits within some
    -- reasonably small size. This counter increments for each character of
    -- text output, not including indentation. It's used to clump things
    -- together as needed (see the clump function).
    cs_length :: SmallSize,

    cs_indent :: Integer,
    cs_output :: String
}

type ConcreteM = State CS

-- | Convert an abstract syntactic construct to concrete yices syntax.
class Concrete a where
    concreteM :: a -> ConcreteM ()
   

incr :: Integer -> Integer
incr = (+ 1)

indent :: ConcreteM a -> ConcreteM a
indent x = do
    nice <- gets cs_pretty
    if nice
      then do
        ident <- gets cs_indent
        modifyS $ \cs -> cs {cs_indent = incr $! ident }
        r <- x
        modify $ \cs -> cs { cs_indent = ident }
        return r
      else x

indented :: Integer -> String -> String
indented 0 s = s
indented n s = ' ' : indented (n-1) s

line :: String -> ConcreteM ()
line str = do
    cs <- get
    let ident = cs_indent cs
    let sep = case (cs_pretty cs, str, take 1 (cs_output cs)) of
                (True, _, _) -> "\n"
                (False, "(", _) -> ""
                (False, _, ")") -> ""
                _ -> " "
    put $! cs { cs_output = indented ident $! (str ++ sep ++ cs_output cs),
                cs_length = cs_length cs + genericLength str + 1}

-- | Clump together all the text output by the given ConcreteM if it's a small
-- size and we have pretty printing turned on.
clump :: ConcreteM () -> ConcreteM ()
clump x = do
    nice <- gets cs_pretty
    case nice of
      False -> x
      True -> do
        cs <- get
        put $! cs { cs_length = 0 } 
        x
        len <- gets cs_length
        case len of
            Big -> return ()
            Small _ -> do
                -- It's small, so without pretty it will still look nice.
                -- Re-run the output that way.
                put cs
                line $ evalState (x >> gets cs_output) (CS False 0 0 "")

-- | Given the name of an element e and a list of components [a, b, ...],
-- generate a the grouping: (e a b ...)
group :: String -> [ConcreteM ()] -> ConcreteM ()
group str elems = do
    line ")"
    indent $ sequence (reverse elems)
    line $ "(" ++ str
    
instance Concrete Command where
    concreteM (Declare s t)
      = clump $ group ("declare-fun " ++ s ++ " ()") [concreteM t]
    concreteM  (Assert e)
      = clump $ group "assert" [concreteM e]
    concreteM Check = line "(check-sat)"
    concreteM Push = line "(push 1)"
    concreteM Pop = line "(pop 1)"

instance Concrete [Command] where
    concreteM cmds = mapM_ concreteM (reverse cmds)

instance Concrete Type where
    concreteM (ArrowT ts) = error $ "ArrowT not supported in SMTLIB2"
    concreteM (BitVectorT i) = line $ "(_ BitVec " ++ show i ++ ")"
    concreteM IntegerT = line "Int"
    concreteM BoolT = line "Bool"

instance Concrete Expression where
    concreteM (LitE l) = concreteM l
    concreteM (VarE s) = line s
    concreteM (LetE bindings e) = clump $ 
      group "let" [group "" (map concreteM bindings), concreteM e]
    concreteM (AppE f args) = clump $ 
      group "" (concreteM f : map concreteM args)
    concreteM (UpdateE f es e) = error $ "functional update not supported by SMTLIB2"

instance Concrete Binding where
    concreteM (n, e) = clump $ group n [concreteM e]

instance Concrete Literal where
    concreteM (BoolL True) = line "true"
    concreteM (BoolL False) = line "false"
    concreteM (IntegerL i) = line (show i)

-- | Render abstract syntax to a concreteM syntax string meant to be
-- read by a human.
pretty :: Concrete a => a -> String
pretty x = evalState (concreteM x >> gets cs_output) (CS True 0 0 "")

-- | Render abstract syntax to a concreteM syntax string meant to be
-- read by a machine.
concrete :: Concrete a => a -> String
concrete x = evalState (concreteM x >> gets cs_output) (CS False 0 0 "")
