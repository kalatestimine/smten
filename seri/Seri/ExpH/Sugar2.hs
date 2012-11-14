
-- | More syntactic sugar for ExpH.
-- These make use of SeriEHs.
module Seri.ExpH.Sugar2 (
    ifEH, errorEH,
    ) where

import Seri.Sig
import Seri.Name
import Seri.Type
import Seri.ExpH.ExpH
import Seri.ExpH.Sugar
import Seri.ExpH.SeriEH
import Seri.ExpH.SeriEHs
import Seri.ExpH.Typeof

errorEH :: Type -> String -> ExpH
errorEH t msg = appEH (varEH (Sig (name "Prelude.error") (arrowsT [stringT, t]))) (seriEH msg)

ifEH :: ExpH -> ExpH -> ExpH -> ExpH
ifEH p a b = CaseEH ES_None p (Sig (name "True") boolT) a b
