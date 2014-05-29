
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE UnboxedTuples #-}
module Smten.Base.GHC.Show (
    ShowS, Show(..),

    shows, showChar, showString, showMultiLineString,
    showParen, showList__, showSpace,
    showLitChar, showLitString, protectEsc,
    intToDigit, showSignedInt,
    appPrec, appPrec1,
    asciiTab,
    ) where

import GHC.Base
import GHC.Num
import Data.Maybe
import GHC.List((!!), break)
import Smten.Data.Show0 (integer_showsPrec)

type ShowS = String -> String

class Show a where
    showsPrec :: Int -> a -> ShowS
    show :: a -> String
    showList :: [a] -> ShowS

    showsPrec _ x s = show x ++ s
    show x= shows x ""
    showList ls s = showList__ shows ls s

showList__ :: (a -> ShowS) -> [a] -> ShowS
showList__ _ [] s = "[]" ++ s
showList__ showx (x:xs) s = '[' : showx x (showl xs)
  where showl [] = ']' : s
        showl (y:ys) = ',' : showx y (showl ys)

appPrec, appPrec1 :: Int
appPrec = I# 10#
appPrec1 = I# 11#


instance Show () where
    show () = "()"

instance (Show a) => Show [a] where
    showsPrec p = showList

instance Show Bool where
    show True = "True"
    show False = "False"

instance Show Ordering where
  showsPrec _ LT = showString "LT"
  showsPrec _ EQ = showString "EQ"
  showsPrec _ GT = showString "GT"

-- TODO: Implement this like they do in GHC.Show, not with
-- char_showsPrec and char_showList as primitives.
instance Show Char where
    showsPrec _ '\'' = showString "'\\''"
    showsPrec _ c    = showChar '\'' . showLitChar c . showChar '\''

    showList cs = showChar '"' . showLitString cs . showChar '"'

instance Show Int where
    showsPrec = showSignedInt

instance Show a => Show (Maybe a) where
    showsPrec _p Nothing s = showString "Nothing" s
    showsPrec p (Just x) s
                          = (showParen (p > appPrec) $
                             showString "Just " .
                             showsPrec appPrec1 x) s

instance (Show a, Show b) => Show (a, b) where
    show (a, b) = "(" ++ show a ++ "," ++ show b ++ ")"

instance (Show a, Show b, Show c) => Show (a, b, c) where
    show (a, b, c) = "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ")"

instance (Show a, Show b, Show c, Show d) => Show (a, b, c, d) where
    show (a, b, c, d) = "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ "," ++ show d ++ ")"


shows :: (Show a) => a -> ShowS
shows = showsPrec 0

showChar :: Char -> ShowS
showChar = (:)

showString :: String -> ShowS
showString = (++)

showParen :: Bool -> ShowS -> ShowS
showParen b p =
  case b of
    True -> showChar '(' . p . showChar ')' 
    False -> p

showSpace :: ShowS
showSpace = \ xs -> ' ' : xs

showLitChar                :: Char -> ShowS
showLitChar c s | c > '\DEL' =  showChar '\\' (protectEsc isDec (shows (ord c)) s)
showLitChar '\DEL'         s =  showString "\\DEL" s
showLitChar '\\'           s =  showString "\\\\" s
showLitChar c s | c >= ' '   =  showChar c s
showLitChar '\a'           s =  showString "\\a" s
showLitChar '\b'           s =  showString "\\b" s
showLitChar '\f'           s =  showString "\\f" s
showLitChar '\n'           s =  showString "\\n" s
showLitChar '\r'           s =  showString "\\r" s
showLitChar '\t'           s =  showString "\\t" s
showLitChar '\v'           s =  showString "\\v" s
showLitChar '\SO'          s =  protectEsc (== 'H') (showString "\\SO") s
showLitChar c              s =  showString ('\\' : asciiTab!!ord c) s

showLitString :: String -> ShowS
showLitString []         s = s
showLitString ('"' : cs) s = showString "\\\"" (showLitString cs s)
showLitString (c   : cs) s = showLitChar c (showLitString cs s)

showMultiLineString :: String -> [String]
showMultiLineString str
  = go '\"' str
  where
    go ch s = case break (== '\n') s of
                (l, _:s'@(_:_)) -> (ch : showLitString l "\\") : go '\\' s'
                (l, _)          -> [ch : showLitString l "\""]

isDec :: Char -> Bool
isDec c = c >= '0' && c <= '9'

protectEsc :: (Char -> Bool) -> ShowS -> ShowS
protectEsc p f             = f . cont
                             where cont s@(c:_) | p c = "\\&" ++ s
                                   cont s             = s


asciiTab :: [String]
asciiTab = -- Using an array drags in the array module.  listArray ('\NUL', ' ')
           ["NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
            "BS",  "HT",  "LF",  "VT",  "FF",  "CR",  "SO",  "SI",
            "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
            "CAN", "EM",  "SUB", "ESC", "FS",  "GS",  "RS",  "US",
            "SP"]

intToDigit :: Int -> Char
intToDigit (I# i)
    | i >=# 0#  && i <=#  9# =  unsafeChr (ord '0' + I# i)
    | i >=# 10# && i <=# 15# =  unsafeChr (ord 'a' + I# i - 10)
    | otherwise           =  error ("Char.intToDigit: not a digit " ++ show (I# i))

showSignedInt :: Int -> Int -> ShowS
showSignedInt (I# p) (I# n) r
    | n <# 0# && p ># 6# = '(' : itos n (')' : r)
    | otherwise          = itos n r

itos :: Int# -> String -> String
itos n# cs
    | n# <# 0# =
        let !(I# minInt#) = minInt in
        if n# ==# minInt#
                -- negateInt# minInt overflows, so we can't do that:
           then '-' : (case n# `quotRemInt#` 10# of
                       (# q, r #) ->
                           itos' (negateInt# q) (itos' (negateInt# r) cs))
           else '-' : itos' (negateInt# n#) cs
    | otherwise = itos' n# cs
    where
    itos' :: Int# -> String -> String
    itos' x# cs'
        | x# <# 10#  = C# (chr# (ord# '0'# +# x#)) : cs'
        | otherwise = case x# `quotRemInt#` 10# of
                      (# q, r #) ->
                          case chr# (ord# '0'# +# r) of
                          c# ->
                              itos' q (C# c# : cs')

-- TODO: Implement this like they do in GHC.Show, not with integer_showsPrec
-- as a primitive
instance Show Integer where
    showsPrec = integer_showsPrec


