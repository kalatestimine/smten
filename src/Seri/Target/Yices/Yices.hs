
module Seri.Target.Yices.Yices (yicesY) where

import qualified Math.SMT.Yices.Syntax as Y

import Seri.Failable
import Seri.Lambda
import Seri.Target.Yices.Compiler

-- Translate a seri expression to a yices expression
yExp :: YCompiler -> Exp -> Failable Y.ExpY
yExp _ (IntegerE x) = return $ Y.LitI x
yExp _ e@(CaseE _ []) = fail $ "empty case statement: " ++ pretty e
yExp c (CaseE e ms) =
  let -- depat p e
      --    outputs: (predicate, bindings)
      --   predicate - predicates indicating if the 
      --                pattern p matches expression e
      --   bindings - a list of bindings made when p matches e.
      depat :: Pat -> Y.ExpY -> ([Y.ExpY], [((String, Maybe Y.TypY), Y.ExpY)])
      depat (ConP _ n ps) e =
        let (preds, binds) = unzip [depat p (Y.APP (Y.VarE (yicesname n ++ show i)) [e])
                                    | (p, i) <- zip ps [0..]]
            mypred = Y.APP (Y.VarE (yicesname n ++ "?")) [e]
        in (mypred:(concat preds), concat binds)
      depat (VarP (Sig n t)) e = ([], [((n, attemptM $ compile_type c c t), e)])
      depat (IntegerP i) e = ([Y.LitI i Y.:= e], [])
      depat (WildP _) _ = ([], [])

      -- take the AND of a list of predicates in a reasonable way.
      yand :: [Y.ExpY] -> Y.ExpY
      yand [] = Y.VarE "true"
      yand [x] = x
      yand xs = Y.AND xs

      -- dematch e ms
      --    e - the expression being cased on
      --    ms - the remaining matches in the case statement.
      --  outputs - the yices expression implementing the matches.
      dematch :: Y.ExpY -> [Match] -> Failable Y.ExpY
      dematch e [Match p b] = do
          -- TODO: don't assume the last alternative will always be taken.
          let ConT dn = typeof b
          b' <- compile_exp c c b
          let (_, bindings) = depat p e
          return $ Y.LET bindings b'
      dematch e ((Match p b):ms) = do
          bms <- dematch e ms
          b' <- compile_exp c c b
          let (preds, bindings) = depat p e
          let pred = yand preds
          return $ Y.IF pred (Y.LET bindings b') bms
  in do
      e' <- compile_exp c c e
      dematch e' ms
yExp c (AppE a b) = do
    a' <- compile_exp c c a
    b' <- compile_exp c c b
    return $ Y.APP a' [b']
yExp c (LamE (Sig n t) e) = do
    e' <- compile_exp c c e
    return $ Y.LAMBDA [(n, surely $ compile_type c c t)] e'
yExp _ (ConE (Sig n _)) = return $ Y.VarE (yicescon n)
yExp _ (VarE (Sig n _)) = return $ Y.VarE (yicesname n)

-- Yices data constructors don't support partial application, so we wrap them in
-- functions given by the following name.
yicescon :: Name -> Name
yicescon n = yicesname $ "C" ++ n

yType :: YCompiler -> Type -> Failable Y.TypY
yType _ (ConT n) = return $ Y.VarT (yicesname n)
yType c (AppT (AppT (ConT "->") a) b) = do
    a' <- compile_type c c a
    b' <- compile_type c c b
    return $ Y.ARR [a', b']
yType _ t = fail $ "yicesY does not apply to type: " ++ pretty t

-- yDec
--   Assumes the declaration is monomorphic.
yDec :: YCompiler -> Dec -> Failable [Y.CmdY]
yDec c (ValD (TopSig n [] t) e) = do
    yt <- compile_type c c t
    ye <- compile_exp c c e
    return [Y.DEFINE (yicesname n, yt) (Just ye)]
yDec c (DataD "Integer" _ _) =
    let deftype = Y.DEFTYP "Integer" (Just (Y.VarT "int"))
    in return [deftype]
yDec c (DataD n [] cs) =
    let con :: Con -> Failable (String, [(String, Y.TypY)])
        con (Con n ts) = do 
            ts' <- mapM (compile_type c c) ts
            return (yicesname n, zip [yicesname n ++ show i | i <- [0..]] ts')

        -- Wrap each constructor in a function which supports partial
        -- application.
        mkcons :: Con -> Failable Y.CmdY
        mkcons (Con cn ts) = do
            yts <- mapM (compile_type c c) ts
            let ft a b = Y.ARR [a, b]
            let yt = foldr ft (Y.VarT (yicesname n)) yts
            let fe (n, t) e = Y.LAMBDA [(n, t)] e
            let names = [[c] | c <- take (length ts) "abcdefghijklmnop"]
            let body =  if null ts
                          then Y.VarE (yicesname cn)
                          else Y.APP (Y.VarE (yicesname cn)) (map Y.VarE names)
            let ye = foldr fe body (zip names yts)
            return $ Y.DEFINE (yicescon cn, yt) (Just ye)
    in do
        cs' <- mapM con cs
        let deftype = Y.DEFTYP (yicesname n) (Just (Y.DATATYPE cs'))
        defcons <- mapM mkcons cs
        return $ deftype : defcons

-- Integer Primitives
yDec _ (PrimD (TopSig "__prim_add_Integer" _ _))
 = return [defiop "__prim_add_Integer" "+"]
yDec _ (PrimD (TopSig "__prim_sub_Integer" _ _))
 = return [defbop "__prim_sub_Integer" "-"]
yDec _ (PrimD (TopSig "<" _ _)) = return [defbop "<" "<"]
yDec _ (PrimD (TopSig ">" _ _)) = return [defbop ">" ">"]
yDec _ (PrimD (TopSig "__prim_eq_Integer" _ _))
 = return [defbop "__prim_eq_Integer" "="]

yDec c d = fail $ "yicesY does not apply to dec: " ++ pretty d

yicesY :: YCompiler
yicesY = Compiler yExp yType yDec


-- defiop name type op
--   Define a primitive binary integer operation.
--   name - the name of the primitive
--   op - the integer operation.
defiop :: String -> String -> Y.CmdY
defiop name op =
    Y.DEFINE (yicesname name, Y.VarT "(-> Integer (-> Integer Integer))")
        (Just (Y.VarE $
            "(lambda (a::Integer) (lambda (b::Integer) (" ++ op ++ " a b)))"))

-- defbop name type op
--   Define a primitive binary integer predicate.
--   name - the name of the primitive
--   op - the predicate operator.
defbop :: String -> String -> Y.CmdY
defbop name op =
    Y.DEFINE (yicesname name, Y.VarT "(-> Integer (-> Integer Bool))")
        (Just (Y.VarE $ unlines [
                "(lambda (a::Integer) (lambda (b::Integer)",
                " (if (" ++ op ++ " a b) True False)))"]))

