
import Test.HUnit
import System.Exit

import qualified Seri.Tests
import qualified Seri.Lambda.Parser
import qualified Seri.SMT.Tests
--import qualified Seri.Tibby.Tests

-- Run tests, exiting failure if any failed, exiting success if all succeeded.
runtests :: Test -> IO ()
runtests t = do
    cnts <- runTestTT t
    putStrLn $ show cnts
    if (errors cnts + failures cnts > 0)
        then exitFailure
        else exitWith ExitSuccess

tests = "Tests" ~: [
    Seri.Lambda.Parser.tests,
    Seri.Tests.tests,
    Seri.SMT.Tests.tests
--    Seri.Tibby.Tests.tests
    ]

main :: IO ()
main = runtests tests

