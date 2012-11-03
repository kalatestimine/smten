-------------------------------------------------------------------------------
-- Copyright (c) 2012      SRI International, Inc. 
-- All rights reserved.
--
-- This software was developed by SRI International and the University of
-- Cambridge Computer Laboratory under DARPA/AFRL contract (FA8750-10-C-0237)
-- ("CTSRD"), as part of the DARPA CRASH research programme.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
-------------------------------------------------------------------------------
--
-- Authors: 
--   Richard Uhler <ruhler@csail.mit.edu>
-- 
-------------------------------------------------------------------------------

module Seri.Lambda (
    loadenv,
    module Seri.Lambda.Declarations,
    module Seri.Lambda.Env,
    module Seri.Lambda.Generics,
    module Seri.Lambda.IR,
    module Seri.Lambda.Loader,
    module Seri.Lambda.Modularity,
    module Seri.Lambda.Parser,
    module Seri.Lambda.Prelude,
    module Seri.Lambda.Ppr,
    module Seri.Lambda.TypeCheck,
    module Seri.Lambda.TypeInfer,
    module Seri.Lambda.Types,
    module Seri.Lambda.Utils,
    module Seri.Lambda.Sugar,
  ) where

import Seri.Lambda.Declarations
import Seri.Lambda.Env
import Seri.Lambda.Generics
import Seri.Lambda.IR
import Seri.Lambda.Loader
import Seri.Lambda.Modularity
import Seri.Lambda.Parser
import Seri.Lambda.Prelude
import Seri.Lambda.Ppr(Ppr, pretty)
import Seri.Lambda.TypeCheck
import Seri.Lambda.TypeInfer
import Seri.Lambda.Types
import Seri.Lambda.Utils
import Seri.Lambda.Sugar

import Seri.Failable

-- Load a program into an environment.
-- Performs module flattening, type inference, and type checking.
loadenv :: SearchPath -> FilePath -> IO Env
loadenv path fin = do
    query <- load path fin
    flat <- attemptIO $ flatten query
    decs <- attemptIO $ typeinfer (mkEnv flat) flat
    let env = mkEnv decs
    attemptIO $ typecheck env decs
    return env
