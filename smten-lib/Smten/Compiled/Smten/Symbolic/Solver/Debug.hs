
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Smten.Compiled.Smten.Symbolic.Solver.Debug (debug) where

import System.IO

import qualified Smten.Runtime.Assert as A
import Smten.Runtime.Bit
import Smten.Runtime.Debug
import Smten.Runtime.FreeID
import Smten.Runtime.SolverAST
import Smten.Runtime.Solver
import qualified Smten.Runtime.Types as S
import qualified Smten.Compiled.Smten.Smten.Base as S

data DebugLL = DebugLL {
    dbg_handle :: Handle
}

dbgPutStrLn :: DebugLL -> String -> IO ()
dbgPutStrLn dbg s = hPutStrLn (dbg_handle dbg) s

dbgModelVar :: DebugLL -> (FreeID, S.Any) -> IO ()
dbgModelVar dbg (n, S.BoolA x) = dbgPutStrLn dbg $ freenm n ++ " = " ++ show x
dbgModelVar dbg (n, S.IntegerA (S.Integer x)) = dbgPutStrLn dbg $ freenm n ++ " = " ++ show x
dbgModelVar dbg (n, S.BitA x) = dbgPutStrLn dbg $ freenm n ++ " = " ++ show x

dbgModel :: DebugLL -> S.Model -> IO ()
dbgModel dbg m = mapM_ (dbgModelVar dbg) (S.m_vars m)


-- mark a debug object for sharing.
sh :: Debug -> Debug
sh x = dbgShare id x

op :: String -> DebugLL -> Debug -> Debug -> IO Debug
op o _ a b = return $ dbgOp o (sh a) (sh b)

instance SolverAST DebugLL Debug where
    declare dbg ty nm = do
        dbgPutStrLn dbg $ "declare " ++ nm ++ " :: " ++ show ty

    getBoolValue = error $ "Debug.getBoolValue: not implemented"
    getIntegerValue = error $ "Debug.getIntegerValue: not implemented"
    getBitVectorValue = error $ "Debug.getBitVectorValue: not implemented"
    check = error $ "Debug.check not implemented"

    cleanup dbg = hClose (dbg_handle dbg)

    assert dbg e = do
        dbgPutStrLn dbg "assert:"
        dbgstr <- dbgRender e
        dbgPutStrLn dbg $ dbgstr

    bool dbg b = return $ dbgLit b
    integer dbg i = return $ dbgLit i
    bit dbg w v = return $ dbgLit (bv_make w v)
    var dbg n = return $ dbgVar n

    and_bool = op "&&"
    not_bool dbg x = return $ dbgApp (dbgText "!") (sh x)
    ite_bool dbg p a b = return $ dbgCase "True" (sh p) (sh a) (sh b)
    ite_integer dbg p a b = return $ dbgCase "True" (sh p) (sh a) (sh b)
    ite_bit dbg p a b = return $ dbgCase "True" (sh p) (sh a) (sh b)

    eq_integer = op "=="
    leq_integer = op "<="
    add_integer = op "+"
    sub_integer = op "-"

    eq_bit = op "=="
    leq_bit = op "<="
    add_bit = op "+"
    sub_bit = op "-"
    mul_bit = op "*"
    or_bit = op "|"
    and_bit = op "&"
    concat_bit = op "++"
    shl_bit d _ = op "<<" d
    lshr_bit d _ = op ">>" d
    not_bit dbg x = return $ dbgApp (dbgText "~") (sh x)
    sign_extend_bit dbg fr to x = return $ dbgText "?SignExtend"
    extract_bit dbg hi lo x = return $
      dbgApp (sh x) (dbgText $ "[" ++ show hi ++ ":" ++ show lo ++ "]")

debug :: S.List__ S.Char -> Solver -> Solver
debug fsmten s = Solver $ \vars formula -> do
    let f = S.toHSString fsmten
    fout <- openFile f WriteMode
    hSetBuffering fout NoBuffering
    let dbg = DebugLL fout
    mapM_ (\(nm, ty) -> declare dbg ty (freenm nm)) vars
    A.assert dbg formula
    dbgPutStrLn dbg $ "check... "
    res <- solve s vars formula
    case res of
      Just m -> do
          dbgPutStrLn dbg "Sat"
          dbgModel dbg m
          cleanup dbg
          return (Just m)
      Nothing -> do
          dbgPutStrLn dbg "Unsat"
          cleanup dbg
          return Nothing

