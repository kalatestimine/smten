
{-# LANGUAGE PatternGuards #-}

module Smten.CodeGen (codegen) where

import Data.Functor((<$>))
import Data.Hash.MD5

import System.Directory

import Smten.Failable
import Smten.Module
import Smten.Ppr(pretty)

import Smten.CodeGen.Module
import Smten.CodeGen.Name
import Smten.CodeGen.Ppr ()

codegen :: FilePath -> [Module] -> IO ()
codegen odir mods = {-# SCC "CodeGEn" #-} do
  let env = environ mods
      mkmod m = do
        hf <- pretty <$> attemptIO (moduleCG env m)
        let dst = map dot2slash . modprefix . mod_name $ m
            tgt = odir ++ "/" ++ dst ++ ".hs"
        createDirectoryIfMissing True (directory tgt)
        writeFileIfChanged tgt hf
  mapM_ mkmod mods

-- Write to the given file, but only if we are writing something new.
-- This keeps us from touching the timestamp of the file if there is no
-- change, so ghc won't have to recompile that file.
writeFileIfChanged :: FilePath -> String -> IO ()
writeFileIfChanged tgt cnts = do
   exists <- doesFileExist tgt
   if exists 
        then do
            old <- readFile tgt
            if md5 (Data.Hash.MD5.Str old) == md5 (Data.Hash.MD5.Str cnts)
                then return ()
                else writeFile tgt cnts
        else writeFile tgt cnts

directory :: FilePath -> FilePath
directory f
  | '/' `notElem` f = ""
  | (h, t) <- break (== '/') f = h ++ "/" ++ directory (tail t)

dot2slash :: Char -> Char
dot2slash '.' = '/'
dot2slash c = c 

