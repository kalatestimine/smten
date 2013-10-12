
{-# LANGUAGE MultiParamTypeClasses #-}

module Smten.Compiled.Smten.Symbolic.Solver.Pure (pure) where

import Control.Monad

import Data.IORef
import Data.Functor

import Smten.Runtime.Types (Type(..))
import Smten.Runtime.Result
import Smten.Runtime.SolverAST
import Smten.Runtime.Solver
import Smten.Runtime.Bits
import Smten.Runtime.Integers

data Model = Model {
    vars :: [(String, Bool)]
}

data Exp = Exp (Model -> Bool)

data PureSolver = PureSolver (IORef [Model])

ite_Exp :: Exp -> Exp -> Exp -> IO Exp
ite_Exp (Exp p) (Exp a) (Exp b) = return . Exp $ \m ->
     case p m of
        True -> a m
        False -> b m

nobits = error "PureSolver: bits not supported natively"
noints = error "PureSolver: integers not supported natively"

instance SolverAST PureSolver Exp where
  declare (PureSolver mref) BoolT nm = do
     ms <- readIORef mref
     writeIORef mref $ do
        vs <- vars <$> ms
        b <- [True, False]
        return (Model $ (nm, b) : vs)

  declare (PureSolver mref) IntegerT nm = noints
  declare (PureSolver mref) (BitT _) nm = nobits

  getBoolValue (PureSolver mref) nm = do
     ms <- readIORef mref
     case ms of
        [] -> error $ "getBoolValue called when there is no model"
        (x:_) ->
          case lookup nm (vars x) of
            Just b -> return b
            Nothing -> error $ "getBoolValue: " ++ nm ++ " not found"
  
  getIntegerValue = noints
  getBitVectorValue = nobits

  check (PureSolver mref) = do
     ms <- readIORef mref
     return (if null ms then Unsat else Sat)

  assert (PureSolver mref) (Exp p) = do
     ms <- readIORef mref
     writeIORef mref $ do
        m <- ms
        guard (p m == True)
        return m

  bool _ x = return (Exp $ const x)
  integer = noints
  bit = nobits

  var _ nm = return . Exp $ \m ->
                case lookup nm (vars m) of
                    Just x -> x
                    Nothing -> error $ "var: " ++ nm ++ " not found"

  and_bool ctx a b = ite_bool ctx a b (Exp $ const False)
  not_bool ctx a = ite_bool ctx a (Exp $ const False) (Exp $ const True)

  ite_bool _ = ite_Exp
  ite_integer = noints
  ite_bit _ = nobits

  eq_integer = noints
  leq_integer = noints
  add_integer = noints
  sub_integer = noints

  eq_bit = nobits
  leq_bit = nobits
  add_bit = nobits
  sub_bit = nobits
  mul_bit = nobits
  or_bit = nobits
  and_bit = nobits
  shl_bit = nobits
  lshr_bit = nobits
  concat_bit = nobits
  not_bit = nobits
  sign_extend_bit = nobits
  extract_bit = nobits

pure :: Solver
pure = do
   mref <- newIORef [Model []]
   let base = PureSolver mref
   withints <- addIntegers base
   withbits <- addBits withints
   return $ solverInstFromAST withbits

