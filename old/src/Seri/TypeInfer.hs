
module Seri.TypeInfer (
    typeinfer
    ) where

import Data.Generics
import Data.Maybe
import Control.Monad.State

import Seri.IR

-- typeinfer 
--  Run typeinference on an expression.
--  Types marked TyUnknown are inferred.
--  Assumes there are no VarT's in the expression.
--  The returned expression has types inferred, but they may be incorrectly
--  inferred if the expression doesn't type check, so you should run typecheck
--  after inference to make sure it's valid.
typeinfer :: Exp -> Exp
typeinfer eorig
 = let (evared, cons) = constraints eorig
       sol = solve cons
   in tereplace sol evared

-- If the given type is in the map, replace it, otherwise keep it unchanged.
replace :: [(Type, Type)] -> Type -> Type
replace l t =
    case lookup t l of
        Just t' -> t'
        Nothing -> t

-- replace each type in expression according to the given association list.
tereplace :: (Data e) => [(Type, Type)] -> e -> e
tereplace l = everywhere (mkT $ replace l)

-- Replace all unknown types with variable types.
-- State is the id of the next free type variable to use.
ununknown :: (Data e) => e -> State Integer e
ununknown = everywhereM (mkM ununknownt)

ununknownt :: Type -> State Integer Type
ununknownt =
    let ununt UnknownT = do
            id <- get
            put (id + 1)
            return $ VarT id
        ununt t = return t
    in everywhereM (mkM ununt)

constraints :: Exp -> (Exp, [(Type, Type)])
constraints e
 = let (vared, nid) = runState (ununknown e) 0
       (_, (_, cs)) = runState (constrain vared) (nid, [])
   in (vared, cs)

-- Generate type constraints for an expression, assuming no UnknownT types are
-- in it.
constrain :: Exp -> State (Integer, [(Type, Type)]) ()
constrain = traverseM $ TraversalM {
    tr_boolM = \_ _ -> return (),
    tr_intM = \_ _ -> return (),
    tr_addM = \(AddE a b) _ _ -> do
        addc IntegerT (typeof a)
        addc IntegerT (typeof b),
    tr_mulM = \(MulE a b) _ _ -> do
        addc IntegerT (typeof a)
        addc IntegerT (typeof b),
    tr_subM = \(SubE a b) _ _ -> do
        addc IntegerT (typeof a)
        addc IntegerT (typeof b),
    tr_ltM = \(LtE a b) _ _ -> do
        addc IntegerT (typeof a)
        addc IntegerT (typeof b),
    tr_ifM = \(IfE t p a b) _ _ _ _ -> do
        addc BoolT (typeof p)
        addc (typeof a) (typeof b),
    tr_appM = \(AppE t f x) _ _ _ -> do
        it <- nextv
        ot <- nextv
        addc (ArrowT it ot) (typeof f)
        addc ot t
        addc it (typeof x),
    tr_fixM = \(FixE t n b) _ _ _ -> do
        addc t (typeof b)
        constrainvs n t b,
    tr_lamM = \(LamE t n b) _ _ _ -> do
        it <- nextv
        ot <- nextv
        addc (ArrowT it ot) t
        addc ot (typeof b)
        constrainvs n it b,
    tr_varM = \_ _ _ -> return ()
}

constrainvs :: Name -> Type -> Exp -> State (Integer, [(Type, Type)]) ()
constrainvs n v = traverse $ Traversal {
    tr_bool = \_ _ -> return (),
    tr_int = \_ _ -> return (),
    tr_add = \_ a b -> a >> b,
    tr_mul = \_ a b -> a >> b,
    tr_sub = \_ a b -> a >> b,
    tr_lt = \_ a b -> a >> b,
    tr_if = \_ _ p a b -> p >> a >> b,
    tr_app = \_ _ a b -> a >> b,
    tr_fix = \_ _ nm b ->
        if n == nm
            then return ()
            else b,
    tr_lam = \_ _ nm b ->
        if n == nm
            then return ()
            else b,
    tr_var = \_ t nm ->
        if n /= nm
            then return ()
            else addc t v
}

addc :: Type -> Type -> State (Integer, [(Type, Type)]) ()
addc a b = do
    (i, cs) <- get  
    put (i, (a, b):cs)

nextv :: State (Integer, [(Type, Type)]) Type
nextv = do
    (i, cs) <- get
    put (i+1, cs)
    return (VarT i)


-- Solve a type constraint system.
--
-- Here's how we solve it:
--    We define an order on Types based on how well known they are. So
--    IntegerT, ArrowT, etc... are very well known. VarT less so, and we say
--    VarT 4 is less known than VarT 1, for instance.
--
--    For any constraint of the form X = Y, we use that to replace every
--    occurence of the less well known type with the more well known type. For
--    example, say Y is less well known. Every occurence of Y in all the
--    constraints is replaced with X, and we add Y = X to the solution set.
--
--    The claim is, after going through each constraint, we are left with
--    the best known definitions of each lesser known type we can find.
--
-- This ignores inconsistent constraints. We'll let the typechecker catch
-- those when checking the solved system, because it can give better error
-- messages.
solve' :: State ([(Type, Type)], [(Type, Type)]) [(Type, Type)]
solve' = do
    (ins, outs) <- get
    case ins of
        [] -> return outs
        (x:xs) -> do
            put (xs, outs)
            solveconstraint x
            solve'

solve :: [(Type, Type)] -> [(Type, Type)]
solve xs = fst $ runState solve' (xs, [])
        
solveconstraint :: (Type, Type) -> State ([(Type, Type)], [(Type, Type)]) ()
solveconstraint (x, y) | x == y = return ()
solveconstraint ((ArrowT a b), (ArrowT c d))
  = solveconstraint (a, c) >> solveconstraint (b, d)
solveconstraint (a, b) | b `lessknown` a = solveconstraint (b, a)
solveconstraint (a, b) = do
    (ins, outs) <- get
    let ins' = map (tpreplace a b) ins
    let outs' = map (tpreplace a b) outs
    put (ins', (a, b):outs')

tpreplace :: Type -> Type -> (Type, Type) -> (Type, Type)
tpreplace k v (a, b) = (treplace k v a, treplace k v b)

-- treplace k v x
-- Replace every occurence of type k in x with type v.
treplace :: Type -> Type -> Type -> Type
treplace k v x | k == x = v
treplace k v (ArrowT a b) = ArrowT (treplace k v a) (treplace k v b)
treplace _ _ x = x 

lessknown :: Type -> Type -> Bool
lessknown (VarT a) (VarT b) = a > b
lessknown (VarT _) BoolT = True
lessknown (VarT _) IntegerT = True
lessknown (VarT _) (ArrowT _ _) = True
lessknown UnknownT _ = error $ "UnknownT found in lessknown"
lessknown _ UnknownT = error $ "UnknownT found in lessknown"
lessknown a b = False
