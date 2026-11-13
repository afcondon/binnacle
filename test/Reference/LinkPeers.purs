-- | The REFERENCE for `/link/peers`. The declaration it implements is
-- | `conformance/LINK-PEERS.md`; the vectors every implementation replays
-- | are generated from here by `make vectors`.
-- |
-- | The message is described once, in `Reference.Described`, and everything
-- | here is derived from that description by Hawser. Until 2026-11-13 this
-- | module was written out by hand; the description was held to that
-- | version on every case before it replaced it, and the vector file did
-- | not change. It lives under `test/` because no browser reads this
-- | message.
module Reference.LinkPeers
  ( Refusal
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
import Data.Either (Either(..))
import Hawser.Bytes (int32ToBytes)
import Hawser.Osc as Osc
import Reference.Described (peers)

-- | Why a packet is not a count we will use: the declaration's tag, or
-- | `not-peers` for a packet that was never this message.
type Refusal = String

notPeers :: Refusal
notPeers = "not-peers"

header :: Array Int
header = Osc.header peers

packetLength :: Int
packetLength = Osc.packetLength peers

-- | The packet for a valid count. A producer sends nothing else.
encode :: Int -> Either Refusal (Array Int)
encode count = Osc.encode peers { peers: count }

-- | The packet for any count, valid or not. For building test vectors.
encodeUnchecked :: Int -> Array Int
encodeUnchecked count = Osc.encodeUnchecked peers { peers: count }

-- | Read one UDP datagram.
decode :: Array Int -> Either Refusal Int
decode packet = case Osc.decode peers packet of
  Osc.Accept record -> Right record.peers
  Osc.Refuse tag -> Left tag
  Osc.Other -> Left notPeers

verdictOf :: forall a. Either Refusal a -> Verdict
verdictOf = case _ of
  Right _ -> Accept
  Left refusal | refusal == notPeers -> Other
  Left _ -> Refuse

refusalName :: Refusal -> String
refusalName = identity

int32Bytes :: Int -> Array Int
int32Bytes = int32ToBytes
