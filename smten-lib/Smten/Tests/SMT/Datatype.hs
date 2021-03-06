
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Tests.SMT.Datatype (smttests, tests) where

import Smten.Prelude
import Smten.Control.Monad
import Smten.Search
import Smten.Search.Solver.Smten
import Smten.Tests.SMT.Test

data MyEnum = E1 | E2 | E3 | E4
    deriving (Eq)

free_MyEnum :: Space MyEnum
free_MyEnum = msum (map return [E1, E2, E3, E4])

rotateenum :: MyEnum -> MyEnum
rotateenum E1 = E2
rotateenum E2 = E1
rotateenum E3 = E4
rotateenum _ = E3

data MyStruct = MyStruct MyEnum Bool
    deriving (Eq)

free_MyStruct :: Space MyStruct
free_MyStruct = do
    a <- free_MyEnum
    b <- free_Bool
    return (MyStruct a b)

changestruct :: MyStruct -> MyStruct
changestruct (MyStruct e True) = MyStruct (rotateenum e) False
changestruct (MyStruct e _) = MyStruct e True

data MyMix = Mix1 Bool Bool
           | Mix2 Bool
    deriving (Eq)

free_MyMix :: Space MyMix
free_MyMix = 
  let f1 = do
        a <- free_Bool
        b <- free_Bool
        return (Mix1 a b)
      f2 = do
        a <- free_Bool
        return (Mix2 a)
  in mplus f1 f2
    

mixval :: MyMix -> MyEnum
mixval (Mix1 True _) = E1
mixval (Mix1 _ _) = E2
mixval (Mix2 True) = E3
mixval _ = E4

smttests :: SMTTest ()
smttests = do
    symtesteq "Datatype.Enum" (Just E4) $ do
        a <- free_MyEnum
        guard (rotateenum a == E3)
        return a

    symtesteq "Datatype.Struct" (Just (MyStruct E1 True)) $ do
        b <- free_MyStruct
        guard (changestruct b == MyStruct E2 False)
        return b
    
    symtesteq "Datatype.Mix" (Just (Mix2 True)) $ do
        c <- free_MyMix
        guard (mixval c == E3)
        return c

    symtesteq "Datatype.Caseoflet" (Just False) $ do
        d <- free_Bool
        guard (case (let v = d || d
                      in if v then E1 else E2) of
                   E1 -> False
                   E2 -> True
                 )
        return d

tests :: IO ()
tests = do
   runtest (SMTTestCfg smten [] []) smttests
   putStrLn "SMT.DataType PASSED"

