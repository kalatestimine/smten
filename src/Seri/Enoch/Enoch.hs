
module Seri.Enoch.Enoch (
    TExp(..), Seriable(..), unpack',
 ) where

import Seri.Lambda

-- | Typed Exp.
-- A Seri expression corresponding to a haskell object of type 'a'
data TExp a = Exp

class Seriable a where
    -- Convert a haskell object to its seri representation.
    pack :: a -> TExp a

    -- Convert a seri representation to its haskell object
    unpack :: TExp a -> Maybe a

    -- The seri type corresponding to the type 'a'.
    -- The argument is ignored.
    serit :: a -> Type


unpack' :: TExp a -> a
unpack' = fromMaybe (error "unpack' failed") . unpack

