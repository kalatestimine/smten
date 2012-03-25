
module Seri.Elaborate (
    elaborate
    ) where

import Seri.IR

-- elaborate prg
-- Reduce the given expression as much as possible.
elaborate :: Exp -> Exp
elaborate = traverse $ Traversal {
    tr_int = \e _ -> e,
    tr_add = \_ a b ->
        case (a, b) of
            (IntegerE av, IntegerE bv) -> IntegerE (av+bv)
            _ -> AddE a b,
    tr_mul = \_ a b ->
        case (a, b) of
            (IntegerE av, IntegerE bv) -> IntegerE (av*bv)
            _ -> MulE a b,
    tr_sub = \_ a b ->
        case (a, b) of
            (IntegerE av, IntegerE bv) -> IntegerE (av-bv)
            _ -> SubE a b,
    tr_app = \_ t f x ->
        case f of
            (LamE _ name body) -> elaborate $ reduce name x body
            _ -> AppE t f x,
    tr_lam = \e _ _ _ -> e,
    tr_var = \e _ _ -> e
}


-- reduce n v exp
-- Perform beta reduction in exp, replacing occurances of variable n with v.
reduce :: Name -> Exp -> Exp -> Exp
reduce n v = traverse $ Traversal {
    tr_int = \e _ -> e,
    tr_add = \_ -> AddE,
    tr_mul = \_ -> MulE,
    tr_sub = \_ -> SubE,
    tr_app = \_ -> AppE,
    tr_lam = \e t ln b -> if ln /= n then LamE t ln b else e,
    tr_var = \e t vn -> if vn == n then v else e
}

