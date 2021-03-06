
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Tests.List (tests) where

import Smten.Prelude
import Smten.Data.List
import Smten.Tests.Test

tests :: IO ()
tests = do
   test "tails" (tails "abc" == ["abc", "bc", "c", ""])
   test "isPrefixOf" (isPrefixOf "foo" "foosball")
   test "not isPrefixOf" (not $ isPrefixOf "fish" "foosball")
   test "isInfixOf" (isInfixOf "oba" "foobar")
   test "not isInfixOf" (not $ isInfixOf "abo" "foobar")
   test "nub" (nub "abaabccabdabeaabc" == "abcde")
   test "sort" (sort [8, 10, 2, 6, 2, 7, 4, 3, 10, 0, 5 :: Integer]
                  == [0, 2, 2, 3, 4, 5, 6, 7, 8, 10, 10])

   putStrLn "List PASSED"

