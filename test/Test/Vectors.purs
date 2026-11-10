-- | The conformance cases for `/link/anchor`, with the verdict each one is
-- | DECLARED to have. `Test.Main` checks that the reference agrees with every
-- | declaration; `Test.Generate` writes them out as the vector file the other
-- | implementations replay.
-- |
-- | The verdicts here are written by hand on purpose. If they were computed
-- | from `Binnacle.Anchor` the file could only ever say what the code does.
module Test.Vectors
  ( OscCase
  , TextCase
  , BeatCase
  , FreshCase
  , canonical
  , canonicalHex
  , oscCases
  , textCases
  , beatCases
  , freshCases
  , beatTolerance
  ) where

import Prelude

import Binnacle.Anchor (Anchor(..), Verdict(..), encodeOscUnchecked, float64Bytes, int64Bytes, oscHeader)
import Data.Array as Array
import Data.Char (toCharCode)
import Data.Maybe (Maybe(..))
import Data.String.CodeUnits (toCharArray)

type OscCase =
  { name :: String
  , bytes :: Array Int
  , expect :: Verdict
  , anchor :: Maybe Anchor
  , why :: String
  }

type TextCase =
  { name :: String
  , line :: String
  , expect :: Verdict
  , anchor :: Maybe Anchor
  , why :: String
  }

type BeatCase =
  { name :: String
  , anchor :: Anchor
  , atUnixMicros :: Number
  , beat :: Number
  }

type FreshCase =
  { ageMicros :: Number
  , fresh :: Boolean
  }

type Fields =
  { unixMicros :: Number
  , beat :: Number
  , tempo :: Number
  , quantum :: Number
  }

-- | 2026-11-10 16:00:00 UTC, beat 128.5, 120 bpm, four beats to the bar.
canonicalFields :: Fields
canonicalFields =
  { unixMicros: 1794326400000000.0
  , beat: 128.5
  , tempo: 120.0
  , quantum: 4.0
  }

canonical :: Anchor
canonical = Anchor canonicalFields

-- | The canonical packet, computed independently of this codebase with
-- | Python's `struct.pack('>qddd', ...)`. It pins the encoder to something
-- | other than itself.
canonicalHex :: String
canonicalHex =
  "2f6c696e6b2f616e63686f72000000002c6864646400000000065fee2baee0004060100000000000405e0000000000004010000000000000"

-- | How close a computed beat must be to the expected one.
beatTolerance :: Number
beatTolerance = 1.0e-9

-- ── OSC ────────────────────────────────────────────────────────────────────

accepted :: String -> Fields -> String -> OscCase
accepted name fields why =
  { name, bytes: encodeOscUnchecked (Anchor fields), expect: Accept, anchor: Just (Anchor fields), why }

refusedValue :: String -> Fields -> String -> OscCase
refusedValue name fields why =
  { name, bytes: encodeOscUnchecked (Anchor fields), expect: Refuse, anchor: Nothing, why }

refusedBytes :: String -> Array Int -> String -> OscCase
refusedBytes name bytes why = { name, bytes, expect: Refuse, anchor: Nothing, why }

otherBytes :: String -> Array Int -> String -> OscCase
otherBytes name bytes why = { name, bytes, expect: Other, anchor: Nothing, why }

canonicalPacket :: Array Int
canonicalPacket = encodeOscUnchecked canonical

-- | The canonical packet with one eight-byte argument replaced.
withArgument :: Int -> Array Int -> Array Int
withArgument index replacement =
  Array.take (24 + 8 * index) canonicalPacket
    <> replacement
    <> Array.drop (32 + 8 * index) canonicalPacket

-- | A packet with our address, different type tags, and whatever follows.
withTags :: String -> Array Int -> Array Int
withTags tags arguments = Array.take 16 oscHeader <> oscString tags <> arguments

-- | An OSC string: the characters, a NUL, then NULs to a multiple of four.
oscString :: String -> Array Int
oscString text =
  let
    characters = map toCharCode (toCharArray text) <> [ 0 ]
    padding = (4 - Array.length characters `mod` 4) `mod` 4
  in
    characters <> Array.replicate padding 0

nan :: Number
nan = 0.0 / 0.0

infinity :: Number
infinity = 1.0 / 0.0

oscCases :: Array OscCase
oscCases =
  -- Accepted.
  [ accepted "canonical" canonicalFields "an ordinary anchor"
  , accepted "tempo-at-minimum" (canonicalFields { tempo = 20.0 }) "20 bpm is inside the range"
  , accepted "tempo-at-maximum" (canonicalFields { tempo = 999.0 }) "999 bpm is inside the range"
  , accepted "tempo-fractional" (canonicalFields { tempo = 97.3 }) "tempo is not an integer"
  , accepted "quantum-at-minimum" (canonicalFields { quantum = 1.0 }) "one beat to the bar"
  , accepted "quantum-at-maximum" (canonicalFields { quantum = 64.0 }) "sixty-four beats to the bar"
  , accepted "quantum-fractional" (canonicalFields { quantum = 3.5 }) "quantum is not required to be whole"
  , accepted "beat-negative" (canonicalFields { beat = -3.25 }) "Link's beat is negative before the session's origin"
  , accepted "beat-zero" (canonicalFields { beat = 0.0 }) "the origin itself"
  , accepted "beat-large" (canonicalFields { beat = 1234567.875 }) "a session that has run for days"
  , accepted "unix-micros-zero" (canonicalFields { unixMicros = 0.0 }) "the epoch is the lowest time allowed"
  , accepted "unix-micros-largest" (canonicalFields { unixMicros = 9007199254740991.0 }) "2^53 - 1 is the highest time allowed"

  -- Refused for a value.
  , refusedValue "tempo-below-minimum" (canonicalFields { tempo = 19.999 }) "just under 20 bpm"
  , refusedValue "tempo-above-maximum" (canonicalFields { tempo = 999.001 }) "just over 999 bpm"
  , refusedValue "tempo-zero" (canonicalFields { tempo = 0.0 }) "a bar would be infinitely long"
  , refusedValue "tempo-negative" (canonicalFields { tempo = -120.0 }) "time does not run backwards"
  , refusedValue "tempo-nan" (canonicalFields { tempo = nan }) "NaN, the quiet one every platform writes"
  , refusedValue "tempo-infinite" (canonicalFields { tempo = infinity }) "positive infinity"
  , refusedValue "beat-nan" (canonicalFields { beat = nan }) "a NaN beat would put NaN on every clock"
  , refusedValue "beat-infinite" (canonicalFields { beat = infinity }) "positive infinity"
  , refusedValue "beat-negative-infinite" (canonicalFields { beat = -infinity }) "negative infinity"
  , refusedValue "quantum-zero" (canonicalFields { quantum = 0.0 }) "a bar of no beats divides by zero"
  , refusedValue "quantum-below-minimum" (canonicalFields { quantum = 0.999 }) "just under one"
  , refusedValue "quantum-above-maximum" (canonicalFields { quantum = 64.001 }) "just over sixty-four"
  , refusedValue "quantum-nan" (canonicalFields { quantum = nan }) "NaN"
  , refusedValue "unix-micros-too-large" (canonicalFields { unixMicros = 9007199254740992.0 }) "2^53 is one past what a double holds exactly"
  , refusedBytes "unix-micros-minus-one" (withArgument 0 (Array.replicate 8 255)) "a negative int64"
  , refusedBytes "unix-micros-most-negative" (withArgument 0 ([ 128 ] <> Array.replicate 7 0)) "the lowest int64"
  , refusedBytes "beat-nan-with-payload" (withArgument 1 [ 127, 240, 0, 0, 0, 0, 0, 1 ]) "a NaN that is not the canonical quiet one"
  , refusedBytes "tempo-nan-sign-set" (withArgument 2 [ 255, 248, 0, 0, 0, 0, 0, 0 ]) "a NaN with its sign bit set"

  -- Refused for its shape: our address, not our message.
  , refusedBytes "tags-three-arguments" (withTags ",hdd" (Array.drop 24 (Array.take 48 canonicalPacket))) "a well-formed message with the quantum missing"
  , refusedBytes "tags-five-arguments" (withTags ",hdddd" (Array.drop 24 canonicalPacket <> float64Bytes 1.0)) "a well-formed message with one argument too many"
  , refusedBytes "tags-int32-time" (withTags ",iddd" ([ 0, 0, 0, 1 ] <> Array.drop 32 canonicalPacket)) "the time sent as a 32-bit integer"
  , refusedBytes "tags-float32-values" (withTags ",hfff" (int64Bytes canonicalFields.unixMicros <> Array.replicate 12 0)) "the values sent as 32-bit floats"
  , refusedBytes "tags-double-time" (withTags ",dddd" (Array.drop 24 canonicalPacket)) "the time sent as a double"
  , refusedBytes "address-only" (Array.take 16 canonicalPacket) "cut off before the type tags"
  , refusedBytes "header-only" (Array.take 24 canonicalPacket) "address and tags with no arguments"
  , refusedBytes "truncated-by-four" (Array.take 52 canonicalPacket) "half of the last argument is missing"
  , refusedBytes "trailing-bytes" (canonicalPacket <> [ 0, 0, 0, 0 ]) "four bytes past the end of the message"

  -- Not an anchor at all.
  , otherBytes "empty" [] "an empty datagram"
  , otherBytes "clock-origin" (oscString "/clock/origin" <> oscString ",d" <> float64Bytes 12.0) "the message that shares es9-daemon's port"
  , otherBytes "address-longer" (oscString "/link/anchors" <> oscString ",hddd" <> Array.drop 24 canonicalPacket) "an address that only begins like ours"
  , otherBytes "address-shorter" (oscString "/link/anch" <> oscString ",hddd" <> Array.drop 24 canonicalPacket) "an address that ours only begins like"
  , otherBytes "bundle" (oscString "#bundle" <> Array.replicate 8 0) "an OSC bundle; the producer sends bare messages"
  , otherBytes "three-bytes" [ 47, 108, 105 ] "too short to hold any address"
  ]

-- ── The text frame ─────────────────────────────────────────────────────────

acceptedLine :: String -> String -> Fields -> String -> TextCase
acceptedLine name line fields why =
  { name, line, expect: Accept, anchor: Just (Anchor fields), why }

refusedLine :: String -> String -> String -> TextCase
refusedLine name line why = { name, line, expect: Refuse, anchor: Nothing, why }

otherLine :: String -> String -> String -> TextCase
otherLine name line why = { name, line, expect: Other, anchor: Nothing, why }

textCases :: Array TextCase
textCases =
  [ acceptedLine "canonical" "anchor 1794326400000000 128.5 120 4" canonicalFields "the shortest spelling"
  , acceptedLine "six-decimals" "anchor 1794326400000000 128.500000 120.000000 4.000000" canonicalFields "as Erlang's ~f writes it"
  , acceptedLine "exponent" "anchor 1794326400000000 1.285e2 1.2E+2 4e0" canonicalFields "exponents are decimal numbers too"
  , acceptedLine "surrounding-whitespace" "  anchor 1794326400000000 128.5 120 4\n" canonicalFields "leading and trailing whitespace is ignored"
  , acceptedLine "beat-negative" "anchor 1794326400000000 -3.25 120 4" (canonicalFields { beat = -3.25 }) "a negative beat"

  , refusedLine "tempo-zero" "anchor 1794326400000000 128.5 0 4" "the same validity rule as the packet"
  , refusedLine "tempo-above-maximum" "anchor 1794326400000000 128.5 1000 4" "the same validity rule as the packet"
  , refusedLine "quantum-zero" "anchor 1794326400000000 128.5 120 0" "the same validity rule as the packet"
  , refusedLine "tempo-nan" "anchor 1794326400000000 128.5 NaN 4" "NaN is not a decimal number"
  , refusedLine "beat-infinity" "anchor 1794326400000000 Infinity 120 4" "Infinity is not a decimal number"
  , refusedLine "four-words" "anchor 1794326400000000 128.5 120" "the quantum is missing"
  , refusedLine "six-words" "anchor 1794326400000000 128.5 120 4 4" "one value too many"
  , refusedLine "double-space" "anchor 1794326400000000  128.5 120 4" "exactly one space between values"
  , refusedLine "time-fractional" "anchor 1794326400000000.5 128.5 120 4" "the time is a whole number of microseconds"
  , refusedLine "time-exponent" "anchor 1.7943264e15 128.5 120 4" "the time is written as digits only"
  , refusedLine "time-negative" "anchor -1 128.5 120 4" "the time is not negative"
  , refusedLine "trailing-unit" "anchor 1794326400000000 128.5 120bpm 4" "a number followed by letters is not a number"
  , refusedLine "leading-plus" "anchor 1794326400000000 +128.5 120 4" "a leading plus sign is not written"
  , refusedLine "bare-fraction" "anchor 1794326400000000 .5 120 4" "a digit comes before the point"
  , refusedLine "anchor-alone" "anchor" "the word with no values"

  , otherLine "empty" "" "an empty frame"
  , otherLine "another-frame" "clock-subscribe" "somebody else's frame"
  , otherLine "capitalised" "Anchor 1794326400000000 128.5 120 4" "the word is lower case"
  , otherLine "prefixed" "anchors 1794326400000000 128.5 120 4" "a word that only begins like ours"
  , otherLine "tab-separated" "anchor\t1794326400000000\t128.5\t120\t4" "words are divided by spaces only, so the first word here is not anchor"
  ]

-- ── Extrapolation ──────────────────────────────────────────────────────────

beatCases :: Array BeatCase
beatCases =
  [ { name: "at-the-anchor", anchor: canonical, atUnixMicros: 1794326400000000.0, beat: 128.5 }
  , { name: "half-a-second-on", anchor: canonical, atUnixMicros: 1794326400500000.0, beat: 129.5 }
  , { name: "one-minute-on", anchor: canonical, atUnixMicros: 1794326460000000.0, beat: 248.5 }
  , { name: "half-a-second-before", anchor: canonical, atUnixMicros: 1794326399500000.0, beat: 127.5 }
  , { name: "one-publish-period-on", anchor: canonical, atUnixMicros: 1794326400100000.0, beat: 128.7 }
  , { name: "sixty-bpm-one-second", anchor: Anchor (canonicalFields { tempo = 60.0, beat = 0.0 }), atUnixMicros: 1794326401000000.0, beat: 1.0 }
  , { name: "fractional-tempo", anchor: Anchor (canonicalFields { tempo = 97.3, beat = -3.25 }), atUnixMicros: 1794326401234567.0, beat: -1.2479438483333336 }
  ]

-- ── Freshness ──────────────────────────────────────────────────────────────

freshCases :: Array FreshCase
freshCases =
  [ { ageMicros: 0.0, fresh: true }
  , { ageMicros: 100000.0, fresh: true }
  , { ageMicros: 1999999.0, fresh: true }
  , { ageMicros: 2000000.0, fresh: true }
  , { ageMicros: 2000001.0, fresh: false }
  , { ageMicros: 60000000.0, fresh: false }
  ]
