module Test.Hex (hex) where

import Prelude

import Data.Int (hexadecimal, toStringAs)
import Data.String as String

-- | Bytes as lower-case hexadecimal, two characters each.
hex :: Array Int -> String
hex = map byte >>> String.joinWith ""
  where
  byte value
    | value < 16 = "0" <> toStringAs hexadecimal value
    | otherwise = toStringAs hexadecimal value
