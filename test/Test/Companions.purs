-- | The conformance cases for `/link/peers` and `/clock/origin`, with the
-- | verdict each one is DECLARED to have, the check that the references
-- | agree, and the two vector files.
-- |
-- | The verdicts are written by hand on purpose, as in `Test.Vectors`.
module Test.Companions
  ( PeersCase
  , OriginCase
  , peersCases
  , originCases
  , failures
  , peersVectors
  , originVectors
  ) where

import Prelude

import Binnacle.Anchor (Verdict(..), encodeOscUnchecked, float64Bytes, verdictName)
import Data.Array as Array
import Data.Char (toCharCode)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String.CodeUnits (toCharArray)
import Foreign (Foreign)
import Reference.ClockOrigin as Origin
import Reference.LinkPeers as Peers
import Simple.JSON (write)
import Test.Hex (hex)
import Test.Vectors (canonical)

type PeersCase =
  { name :: String
  , bytes :: Array Int
  , expect :: Verdict
  , peers :: Maybe Int
  , why :: String
  }

type OriginCase =
  { name :: String
  , bytes :: Array Int
  , expect :: Verdict
  , beat :: Maybe Number
  , why :: String
  }

-- | An OSC string: the characters, a NUL, then NULs to a multiple of four.
oscString :: String -> Array Int
oscString text =
  let
    characters = map toCharCode (toCharArray text) <> [ 0 ]
    padding = (4 - Array.length characters `mod` 4) `mod` 4
  in
    characters <> Array.replicate padding 0

anchorPacket :: Array Int
anchorPacket = encodeOscUnchecked canonical

nan :: Number
nan = 0.0 / 0.0

infinity :: Number
infinity = 1.0 / 0.0

-- ── /link/peers ────────────────────────────────────────────────────────────

-- | Three peers, computed independently of this codebase with Python's
-- | `b'/link/peers\0,i\0\0' + struct.pack('>i', 3)`.
peersCanonicalHex :: String
peersCanonicalHex = "2f6c696e6b2f7065657273002c69000000000003"

peersAddress :: Array Int
peersAddress = oscString "/link/peers"

peersCases :: Array PeersCase
peersCases =
  -- Accepted.
  [ accepted "alone" 0 "no other peer on the session"
  , accepted "three" 3 "an ordinary count"
  , accepted "maximum" 2147483647 "the largest count the packet holds"
  -- Refused: addressed to us and not usable.
  , refused "minus-one" (Peers.encodeUnchecked (-1)) "a count below zero"
  , refused "most-negative" (Peers.encodeUnchecked (-2147483648)) "the top bit set"
  , refused "float-tag" (peersAddress <> oscString ",f" <> [ 64, 64, 0, 0 ]) "a float32 is refused, not converted"
  , refused "long-tag" (peersAddress <> oscString ",h" <> [ 0, 0, 0, 0, 0, 0, 0, 3 ]) "an int64 is refused, not converted"
  , refused "two-integers" (peersAddress <> oscString ",ii" <> Peers.int32Bytes 3 <> Peers.int32Bytes 4) "one argument, not two"
  , refused "no-arguments" (peersAddress <> oscString ",") "the tags say nothing follows"
  , refused "address-only" peersAddress "our address and then nothing"
  , refused "truncated" (Array.take 18 (Peers.encodeUnchecked 3)) "two bytes short"
  , refused "one-byte-over" (Peers.encodeUnchecked 3 <> [ 0 ]) "one byte long"
  -- Other: never this message.
  , other "empty" [] "nothing at all"
  , other "an-anchor" anchorPacket "the anchor arrives on the same port"
  , other "shorter-address" (oscString "/link/peer" <> oscString ",i" <> Peers.int32Bytes 3) "a different address"
  , other "longer-address" (oscString "/link/peersx" <> oscString ",i" <> Peers.int32Bytes 3) "our address is a prefix of it"
  , other "no-terminator" (Array.take 11 peersAddress) "too short to hold the address"
  , other "a-bundle" (oscString "#bundle" <> Array.replicate 8 0) "bundles are never sent"
  ]
  where
  accepted name peers why = { name, bytes: Peers.encodeUnchecked peers, expect: Accept, peers: Just peers, why }
  refused name bytes why = { name, bytes, expect: Refuse, peers: Nothing, why }
  other name bytes why = { name, bytes, expect: Other, peers: Nothing, why }

peersFailures :: Array String
peersFailures =
  canonicalFailure <> Array.concatMap caseFailures peersCases <> duplicateNames "peers" (map _.name peersCases)
  where
  canonicalFailure = case Peers.encode 3 of
    Right bytes | hex bytes == peersCanonicalHex -> []
    _ -> [ "peers: the canonical packet is not " <> peersCanonicalHex ]
  caseFailures testCase =
    let
      label = "peers/" <> testCase.name
      decoded = Peers.decode testCase.bytes
      verdict = Peers.verdictOf decoded
    in
      if verdict /= testCase.expect then
        [ label <> ": declared " <> verdictName testCase.expect <> ", reference says " <> verdictName verdict ]
      else case testCase.peers, decoded of
        Just peers, Right got | got /= peers -> [ label <> ": accepted as " <> show got <> ", declared " <> show peers ]
        Just peers, _ | Peers.encode peers /= Right testCase.bytes -> [ label <> ": encoding the declared count does not give the packet back" ]
        Nothing, Right _ -> [ label <> ": declared to be accepted but no count is declared" ]
        _, _ -> []

-- ── /clock/origin ──────────────────────────────────────────────────────────

-- | Beat 128.5, computed independently of this codebase with Python's
-- | `b'/clock/origin\0\0\0,d\0\0' + struct.pack('>d', 128.5)`.
originCanonicalHex :: String
originCanonicalHex = "2f636c6f636b2f6f726967696e0000002c6400004060100000000000"

originAddress :: Array Int
originAddress = oscString "/clock/origin"

originCases :: Array OriginCase
originCases =
  -- Accepted.
  [ accepted "never-started" 0.0 "beat 0, before any device has been started"
  , accepted "ordinary" 128.5 "a Start that fell between beats"
  , accepted "negative" (-4.0) "Link's beat may be negative"
  , accepted "small-fraction" 1.0e-9 "a tiny beat is still a beat"
  , accepted "very-large" 1.0e300 "finite, however large"
  -- Refused: addressed to us and not usable.
  , refused "not-a-number" (Origin.encodeUnchecked nan) "NaN would outlive the message"
  , refused "infinite" (Origin.encodeUnchecked infinity) "not finite"
  , refused "negative-infinite" (Origin.encodeUnchecked (-infinity)) "not finite"
  , refused "float-tag" (originAddress <> oscString ",f" <> [ 67, 0, 128, 0 ]) "a float32 is refused, not converted"
  , refused "integer-tag" (originAddress <> oscString ",i" <> [ 0, 0, 0, 128 ]) "an integer is refused, not converted"
  , refused "two-doubles" (originAddress <> oscString ",dd" <> float64Bytes 128.5 <> float64Bytes 4.0) "one argument, not two"
  , refused "no-arguments" (originAddress <> oscString ",") "the tags say nothing follows"
  , refused "address-only" originAddress "our address and then nothing"
  , refused "truncated" (Array.take 24 (Origin.encodeUnchecked 128.5)) "four bytes short"
  , refused "four-bytes-over" (Origin.encodeUnchecked 128.5 <> [ 0, 0, 0, 0 ]) "four bytes long"
  -- Other: never this message.
  , other "empty" [] "nothing at all"
  , other "an-anchor" anchorPacket "the anchor arrives on the same port"
  , other "clock-restart" (oscString "/clock/restart") "a different address under /clock"
  , other "longer-address" (oscString "/clock/origins" <> oscString ",d" <> float64Bytes 128.5) "our address is a prefix of it"
  , other "no-terminator" (Array.take 13 originAddress) "too short to hold the address"
  , other "a-bundle" (oscString "#bundle" <> Array.replicate 8 0) "bundles are never sent"
  ]
  where
  accepted name beat why = { name, bytes: Origin.encodeUnchecked beat, expect: Accept, beat: Just beat, why }
  refused name bytes why = { name, bytes, expect: Refuse, beat: Nothing, why }
  other name bytes why = { name, bytes, expect: Other, beat: Nothing, why }

originFailures :: Array String
originFailures =
  canonicalFailure <> Array.concatMap caseFailures originCases <> duplicateNames "origin" (map _.name originCases)
  where
  canonicalFailure = case Origin.encode 128.5 of
    Right bytes | hex bytes == originCanonicalHex -> []
    _ -> [ "origin: the canonical packet is not " <> originCanonicalHex ]
  caseFailures testCase =
    let
      label = "origin/" <> testCase.name
      decoded = Origin.decode testCase.bytes
      verdict = Origin.verdictOf decoded
    in
      if verdict /= testCase.expect then
        [ label <> ": declared " <> verdictName testCase.expect <> ", reference says " <> verdictName verdict ]
      else case testCase.beat, decoded of
        Just beat, Right got | got /= beat -> [ label <> ": accepted as " <> show got <> ", declared " <> show beat ]
        Just beat, _ | Origin.encode beat /= Right testCase.bytes -> [ label <> ": encoding the declared beat does not give the packet back" ]
        Nothing, Right _ -> [ label <> ": declared to be accepted but no beat is declared" ]
        _, _ -> []

-- ── Both ───────────────────────────────────────────────────────────────────

failures :: Array String
failures = peersFailures <> originFailures

duplicateNames :: String -> Array String -> Array String
duplicateNames section names =
  if Array.length (Array.nub names) == Array.length names then []
  else [ section <> ": two cases share a name" ]

-- | The reference's reason, for a case declared to be refused.
reason :: forall a. Verdict -> Either String a -> Maybe String
reason expect actual = case expect, actual of
  Refuse, Left name -> Just name
  _, _ -> Nothing

leftName :: forall refusal a. (refusal -> String) -> Either refusal a -> Either String a
leftName name = case _ of
  Left refusal -> Left (name refusal)
  Right value -> Right value

peersVectors :: Foreign
peersVectors = write
  { "link-peers-vectors": 1
  , declaration: "conformance/LINK-PEERS.md"
  , generatedBy: "Test.Companions in binnacle; do not edit by hand, run `make vectors`"
  , constants: { oscPacketLength: Peers.packetLength, peersMaximum: 2147483647 }
  , osc: peersCases <#> \testCase ->
      { name: testCase.name
      , why: testCase.why
      , hex: hex testCase.bytes
      , expect: verdictName testCase.expect
      , peers: testCase.peers
      , reason: reason testCase.expect (leftName Peers.refusalName (Peers.decode testCase.bytes))
      }
  }

originVectors :: Foreign
originVectors = write
  { "clock-origin-vectors": 1
  , declaration: "conformance/CLOCK-ORIGIN.md"
  , generatedBy: "Test.Companions in binnacle; do not edit by hand, run `make vectors`"
  , constants: { oscPacketLength: Origin.packetLength }
  , osc: originCases <#> \testCase ->
      { name: testCase.name
      , why: testCase.why
      , hex: hex testCase.bytes
      , expect: verdictName testCase.expect
      , beat: testCase.beat
      , reason: reason testCase.expect (leftName Origin.refusalName (Origin.decode testCase.bytes))
      }
  }
