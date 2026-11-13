-- | The REFERENCE for `/clock/origin`. The declaration it implements is
-- | `conformance/CLOCK-ORIGIN.md`; the vectors every implementation replays
-- | are generated from here by `make vectors`.
-- |
-- | Written by hand, in the plainest way, as one half of a spike: see
-- | `docs/kb/plans/wire-declarations.md`, step 1. It lives under `test/`
-- | because no browser reads this message.
module Reference.ClockOrigin
  ( Refusal(..)
  , header
  , packetLength
  , encode
  , encodeUnchecked
  , decode
  , verdictOf
  , refusalName
  ) where

import Prelude

import Binnacle.Anchor (Verdict(..), float64Bytes, float64FromBytes)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Number as Number

data Refusal
  -- | A different message altogether. Not an error, and not counted.
  = NotOrigin
  -- | The address is ours but the type tags are not exactly `,d`.
  | WrongTypeTags
  -- | The address and tags are ours but the packet is not exactly 28 bytes.
  | WrongLength
  -- | The beat is NaN or infinite.
  | NonFiniteValue

derive instance Eq Refusal

-- | `/clock/origin` and `,d`, each NUL-terminated and padded to four bytes.
header :: Array Int
header =
  -- /   c   l    o    c   k    /   o    r    i    g    i    n   NUL padding
  [ 47, 99, 108, 111, 99, 107, 47, 111, 114, 105, 103, 105, 110, 0, 0, 0
  -- ,   d   NUL padding
  , 44, 100, 0, 0
  ]

addressLength :: Int
addressLength = 16

-- | Header (20) plus one float64 (8).
packetLength :: Int
packetLength = 28

-- | The packet for a valid origin. A producer sends nothing else.
encode :: Number -> Either Refusal (Array Int)
encode beat
  | not (Number.isFinite beat) = Left NonFiniteValue
  | otherwise = Right (encodeUnchecked beat)

-- | The packet for any number, valid or not. For building test vectors.
encodeUnchecked :: Number -> Array Int
encodeUnchecked beat = header <> float64Bytes beat

-- | Read one UDP datagram.
decode :: Array Int -> Either Refusal Number
decode bytes
  | Array.take addressLength bytes /= Array.take addressLength header = Left NotOrigin
  | Array.take (Array.length header) bytes /= header = Left WrongTypeTags
  | Array.length bytes /= packetLength = Left WrongLength
  | otherwise =
      let
        beat = float64FromBytes (Array.drop (Array.length header) bytes)
      in
        if Number.isFinite beat then Right beat else Left NonFiniteValue

verdictOf :: forall a. Either Refusal a -> Verdict
verdictOf = case _ of
  Right _ -> Accept
  Left NotOrigin -> Other
  Left _ -> Refuse

refusalName :: Refusal -> String
refusalName = case _ of
  NotOrigin -> "not-origin"
  WrongTypeTags -> "wrong-type-tags"
  WrongLength -> "wrong-length"
  NonFiniteValue -> "non-finite-value"
