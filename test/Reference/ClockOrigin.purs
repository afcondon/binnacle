-- | The REFERENCE for `/clock/origin`. The declaration it implements is
-- | `conformance/CLOCK-ORIGIN.md`; the vectors every implementation replays
-- | are generated from here by `make vectors`.
-- |
-- | The message is described once, in `Reference.Described`, and everything
-- | here is derived from that description by Hawser. Until 2026-11-13 this
-- | module was written out by hand; the description was held to that
-- | version on every case before it replaced it, and the vector file did
-- | not change. It lives under `test/` because no browser reads this
-- | message.
module Reference.ClockOrigin
  ( Refusal
  , header
  , packetLength
  , encode
  , encodeUnchecked
  , decode
  , verdictOf
  , refusalName
  ) where

import Prelude

import Binnacle.Anchor (Verdict(..))
import Data.Either (Either(..))
import Data.Maybe (fromMaybe)
import Hawser.Osc as Osc
import Reference.Described (origin)

-- | Why a packet is not an origin we will use: the declaration's tag, or
-- | `not-origin` for a packet that was never this message.
type Refusal = String

notOrigin :: Refusal
notOrigin = "not-origin"

header :: Array Int
header = Osc.header origin

packetLength :: Int
packetLength = fromMaybe 0 (Osc.packetLength origin)

-- | The packet for a valid origin. A producer sends nothing else.
encode :: Number -> Either Refusal (Array Int)
encode beat = Osc.encode origin { beat }

-- | The packet for any number, valid or not. For building test vectors.
encodeUnchecked :: Number -> Array Int
encodeUnchecked beat = Osc.encodeUnchecked origin { beat }

-- | Read one UDP datagram.
decode :: Array Int -> Either Refusal Number
decode packet = case Osc.decode origin packet of
  Osc.Accept record -> Right record.beat
  Osc.Refuse tag -> Left tag
  Osc.Other -> Left notOrigin

verdictOf :: forall a. Either Refusal a -> Verdict
verdictOf = case _ of
  Right _ -> Accept
  Left refusal | refusal == notOrigin -> Other
  Left _ -> Refuse

refusalName :: Refusal -> String
refusalName = identity
