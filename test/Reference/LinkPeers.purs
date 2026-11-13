-- | The REFERENCE for `/link/peers`. The declaration it implements is
-- | `conformance/LINK-PEERS.md`; the vectors every implementation replays
-- | are generated from here by `make vectors`.
-- |
-- | Written by hand, in the plainest way, as one half of a spike: see
-- | `docs/kb/plans/wire-declarations.md`, step 1. It lives under `test/`
-- | because no browser reads this message.
module Reference.LinkPeers
  ( Refusal(..)
  , header
  , packetLength
  , encode
  , encodeUnchecked
  , decode
  , verdictOf
  , refusalName
  , int32Bytes
  ) where

import Prelude

import Binnacle.Anchor (Verdict(..))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Int.Bits (shl, shr, (.&.), (.|.))

data Refusal
  -- | A different message altogether. Not an error, and not counted.
  = NotPeers
  -- | The address is ours but the type tags are not exactly `,i`.
  | WrongTypeTags
  -- | The address and tags are ours but the packet is not exactly 20 bytes.
  | WrongLength
  -- | The count is below zero.
  | NegativeCount

derive instance Eq Refusal

-- | `/link/peers` and `,i`, each NUL-terminated and padded to four bytes.
header :: Array Int
header =
  -- /   l    i    n    k    /   p    e    e    r    s   NUL
  [ 47, 108, 105, 110, 107, 47, 112, 101, 101, 114, 115, 0
  -- ,   i   NUL padding
  , 44, 105, 0, 0
  ]

addressLength :: Int
addressLength = 12

-- | Header (16) plus one int32 (4).
packetLength :: Int
packetLength = 20

-- | The packet for a valid count. A producer sends nothing else.
encode :: Int -> Either Refusal (Array Int)
encode peers
  | peers < 0 = Left NegativeCount
  | otherwise = Right (encodeUnchecked peers)

-- | The packet for any count, valid or not. For building test vectors.
encodeUnchecked :: Int -> Array Int
encodeUnchecked peers = header <> int32Bytes peers

-- | Read one UDP datagram.
decode :: Array Int -> Either Refusal Int
decode bytes
  | Array.take addressLength bytes /= Array.take addressLength header = Left NotPeers
  | Array.take (Array.length header) bytes /= header = Left WrongTypeTags
  | Array.length bytes /= packetLength = Left WrongLength
  | otherwise =
      case Array.drop (Array.length header) bytes of
        [ first, second, third, fourth ] ->
          let
            peers = (first `shl` 24) .|. (second `shl` 16) .|. (third `shl` 8) .|. fourth
          in
            if peers < 0 then Left NegativeCount else Right peers
        _ -> Left WrongLength

-- | Four big-endian bytes of a signed 32-bit integer.
int32Bytes :: Int -> Array Int
int32Bytes value =
  [ (value `shr` 24) .&. 255
  , (value `shr` 16) .&. 255
  , (value `shr` 8) .&. 255
  , value .&. 255
  ]

verdictOf :: forall a. Either Refusal a -> Verdict
verdictOf = case _ of
  Right _ -> Accept
  Left NotPeers -> Other
  Left _ -> Refuse

refusalName :: Refusal -> String
refusalName = case _ of
  NotPeers -> "not-peers"
  WrongTypeTags -> "wrong-type-tags"
  WrongLength -> "wrong-length"
  NegativeCount -> "negative-count"
