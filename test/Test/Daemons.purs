-- | The conformance cases for the OSC the two Rust daemons read, with the
-- | verdict each is DECLARED to have, the check that the reference agrees,
-- | and the two vector files.
-- |
-- | Four kinds of case:
-- |
-- | * `packets` — what a writer produces. A writer is held to the bytes; a
-- |   reader must accept them and read these values.
-- | * `refused` — addressed to the daemon and not as declared. The
-- |   reference refuses them, and since 2026-11-14 so do both daemons.
-- | * `tolerated` — not as declared, but something on the rig sends it, so
-- |   the daemon must go on reading it until that sender changes. Empty
-- |   since 2026-11-14; the part is kept so that the next such case has a
-- |   place.
-- | * `other` — never one of these messages.
module Test.Daemons
  ( failures
  , summary
  , diaphusVectors
  , es9Vectors
  ) where

import Prelude

import Binnacle.Anchor (encodeOscUnchecked)
import Data.Argonaut.Core (Json)
import Data.Argonaut.Core as Json
import Data.Array as Array
import Data.Char (fromCharCode)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.CodeUnits (fromCharArray)
import Data.Tuple (Tuple(..))
import Foreign.Object as Object
import Hawser.Bytes (float32ToBytes, int32ToBytes)
import Hawser.Osc as Osc
import Wires.Daemons (ToDiaphus(..), ToEs9(..), controlAt, cv, cvTrig, cvTrigAt, encodeToDiaphus, encodeToEs9, esx, esx5Gate, noteAt, noteOnAt, play, setTempo, toDiaphusKinds, toDiaphusMechanical, toEs9Kinds, toEs9Mechanical, valuesToDiaphus, valuesToEs9)
import Test.Hex (hex)
import Test.Vectors (canonical)

type Packet sum = { name :: String, message :: sum, why :: String }
type Refused = { name :: String, bytes :: Array Int, reason :: String, why :: String }
-- | `reads` is what the daemon must take the packet to mean.
type Tolerated sum = { name :: String, bytes :: Array Int, reads :: sum, why :: String }
type Other = { name :: String, bytes :: Array Int, why :: String }

iac :: String
iac = "IAC Driver Tidal"

-- | 2026-11-10 16:00:00 UTC, as in the anchor's canonical case.
then_ :: Number
then_ = 1794326400000000.0

nan :: Number
nan = 0.0 / 0.0

anchorPacket :: Array Int
anchorPacket = encodeOscUnchecked canonical

-- ── To Diaphus ─────────────────────────────────────────────────────────────

-- | Computed independently of this codebase, with Python's `struct`.
noteAtCanonicalHex :: String
noteAtCanonicalHex =
  "2f6d6964692f6e6f74652f61740000002c736969696968004941432044726976657220546964616c00000000000000010000003c00000064000000fa00065fee2baee000"

clockRestartCanonicalHex :: String
clockRestartCanonicalHex = "2f636c6f636b2f7265737461727400002c000000"

diaphusPackets :: Array (Packet ToDiaphus)
diaphusPackets =
  [ packet "note-at" (NoteAt { port: iac, channel: 1, note: 60, velocity: 100, durationMs: 250, unixMicros: then_ }) "an ordinary note"
  , packet "note-at-short-name" (NoteAt { port: "FH-2", channel: 1, note: 60, velocity: 100, durationMs: 250, unixMicros: then_ }) "a name of four characters is followed by four NULs"
  , packet "note-at-extremes" (NoteAt { port: iac, channel: 16, note: 127, velocity: 127, durationMs: 0, unixMicros: 0.0 }) "the top of every range, no length, the epoch"
  , packet "note-at-lowest" (NoteAt { port: iac, channel: 1, note: 0, velocity: 0, durationMs: 1, unixMicros: then_ }) "the bottom of every range"
  , packet "note-at-other-script" (NoteAt { port: "Café ♪", channel: 10, note: 36, velocity: 90, durationMs: 20, unixMicros: then_ }) "a name is UTF-8"
  , packet "note-on-at" (NoteOnAt { port: iac, channel: 1, note: 60, velocity: 100, unixMicros: then_ }) "a note-on alone"
  , packet "note-off-at" (NoteOffAt { port: iac, channel: 1, note: 60, unixMicros: then_ }) "its note-off"
  , packet "cc-at" (ControlAt { port: iac, channel: 1, controller: 7, value: 100, unixMicros: then_ }) "a control change"
  , packet "cc-at-extremes" (ControlAt { port: "FH-2", channel: 16, controller: 127, value: 127, unixMicros: then_ }) "the top of every range"
  , packet "set-tempo" (SetTempo { bpm: 120.0 }) "an ordinary tempo"
  , packet "set-tempo-fractional" (SetTempo { bpm: 97.3 }) "tempo is not an integer"
  , packet "set-tempo-slowest" (SetTempo { bpm: 20.0 }) "Link's floor"
  , packet "set-tempo-fastest" (SetTempo { bpm: 999.0 }) "Link's ceiling"
  , packet "play-start" (Play { on: 1 }) "start on the next bar line"
  , packet "play-stop" (Play { on: 0 }) "stop now"
  , packet "clock-restart" (ClockRestart {}) "no arguments at all"
  ]
  where
  packet name message why = { name, message, why }

diaphusRefused :: Array Refused
diaphusRefused =
  [ refused "note-at-channel-zero" (Osc.encodeUnchecked noteAt (note { channel = 0 })) "channel-out-of-range" "channels are 1 to 16"
  , refused "note-at-channel-seventeen" (Osc.encodeUnchecked noteAt (note { channel = 17 })) "channel-out-of-range" "channels are 1 to 16"
  , refused "note-at-note-too-high" (Osc.encodeUnchecked noteAt (note { note = 128 })) "not-seven-bit" "a note is 0 to 127"
  , refused "note-at-velocity-negative" (Osc.encodeUnchecked noteAt (note { velocity = -1 })) "not-seven-bit" "a velocity is 0 to 127"
  , refused "note-at-duration-negative" (Osc.encodeUnchecked noteAt (note { durationMs = -1 })) "negative-duration" "a length is not negative"
  , refused "note-at-before-epoch" (Osc.encodeUnchecked noteAt (note { unixMicros = -1.0 })) "time-before-epoch" "a moment is not before 1970"
  , refused "note-on-at-channel-zero" (Osc.encodeUnchecked noteOnAt { port: iac, channel: 0, note: 60, velocity: 100, unixMicros: then_ }) "channel-out-of-range" "channels are 1 to 16"
  , refused "cc-at-value-too-high" (Osc.encodeUnchecked controlAt { port: iac, channel: 1, controller: 7, value: 128, unixMicros: then_ }) "not-seven-bit" "a value is 0 to 127"
  , refused "set-tempo-too-slow" (Osc.encodeUnchecked setTempo { bpm: 19.99 }) "tempo-out-of-range" "below Link's floor"
  , refused "set-tempo-too-fast" (Osc.encodeUnchecked setTempo { bpm: 999.01 }) "tempo-out-of-range" "above Link's ceiling"
  , refused "set-tempo-not-a-number" (Osc.encodeUnchecked setTempo { bpm: nan }) "non-finite-value" "a NaN tempo"
  , refused "set-tempo-binary32" (Osc.oscString "/link/set-tempo" <> Osc.oscString ",f" <> float32ToBytes 120.0) "wrong-type-tags" "a binary32 is not what is declared; Architeuthis sent this until 2026-11-14"
  , refused "play-two" (Osc.encodeUnchecked play { on: 2 }) "not-a-flag" "1 or 0"
  ]
    <> map (\testCase -> refused testCase.name testCase.bytes "" testCase.why) (Array.filter (\testCase -> testCase.expect == "refuse") toDiaphusMechanical)
  where
  note = { port: iac, channel: 1, note: 60, velocity: 100, durationMs: 250, unixMicros: then_ }
  refused name bytes reason why = { name, bytes, reason, why }

-- | Nothing. Until 2026-11-14 Architeuthis sent the tempo as a binary32,
-- | and Diaphus read it; Architeuthis now sends through the description, and
-- | that packet is in `diaphusRefused`.
diaphusTolerated :: Array (Tolerated ToDiaphus)
diaphusTolerated = []

diaphusOther :: Array Other
diaphusOther =
  [ { name: "empty", bytes: [], why: "nothing at all" }
  , { name: "an-anchor", bytes: anchorPacket, why: "another message of the rig's" }
  , { name: "unknown-midi-verb", bytes: Osc.oscString "/midi/bend/at" <> Osc.oscString ",siih", why: "an address Diaphus does not read" }
  , { name: "note-at-prefix", bytes: Osc.oscString "/midi/note" <> Osc.oscString ",", why: "a shorter address" }
  ]
    <> map (\testCase -> { name: testCase.name, bytes: testCase.bytes, why: testCase.why })
      (Array.filter (\testCase -> testCase.expect == "other") (Array.take 10 toDiaphusMechanical))

-- ── To es9-daemon ──────────────────────────────────────────────────────────

-- | Computed independently of this codebase, with Python's `struct`.
cvCanonicalHex :: String
cvCanonicalHex = "2f6376002c696600000000083f000000"

es9Packets :: Array (Packet ToEs9)
es9Packets =
  [ packet "cv" (Cv { bus: 8, value: 0.5 }) "panel jack 1 to 5 V"
  , packet "cv-lowest" (Cv { bus: 0, value: -1.0 }) "the first bus, full scale negative"
  , packet "cv-highest" (Cv { bus: 15, value: 1.0 }) "the last bus, full scale"
  , packet "cv-zero" (Cv { bus: 8, value: 0.0 }) "a release"
  , packet "cv-slew" (CvSlew { bus: 8, value: 0.5, lagSeconds: 0.25 }) "a glide"
  , packet "cv-slew-instant" (CvSlew { bus: 8, value: 0.5, lagSeconds: 0.0 }) "no lag is allowed"
  , packet "cv-trig" (CvTrig { bus: 8, value: 0.5, durationMs: 10.0 }) "a ten millisecond trigger"
  , packet "cv-trig-full-scale" (CvTrig { bus: 9, value: 1.0, durationMs: 62.5 }) "as Architeuthis sends it"
  , packet "cv-trig-at" (CvTrigAt { bus: 8, value: 0.5, durationMs: 10.0, delayMs: 62.5 }) "scheduled to the sample"
  , packet "cv-trig-at-now" (CvTrigAt { bus: 8, value: 0.5, durationMs: 10.0, delayMs: 0.0 }) "no delay is allowed"
  , packet "esx" (Esx { slot: 3, value: 0.5 }) "an ESX-8CV output"
  , packet "esx-last" (Esx { slot: 7, value: -1.0 }) "the last output, full scale negative"
  , packet "esx-enable" (EsxEnable { on: 1 }) "the encoding on"
  , packet "esx-disable" (EsxEnable { on: 0 }) "the encoding off"
  , packet "esx5gate-high" (Esx5Gate { bit: 3, state: 1 }) "a gate high"
  , packet "esx5gate-low" (Esx5Gate { bit: 3, state: 0 }) "and low again"
  , packet "tidal-gate" (TidalGate { channel: 2, state: 1 }) "bus 10 high"
  , packet "tidal-gate-trig" (TidalGateTrig { channel: 2, durationMs: 10.0 }) "bus 10 high for a time"
  , packet "tidal-cv" (TidalCv { channel: 1, value: 0.5 }) "bus 13"
  , packet "tidal-cv-slew" (TidalCvSlew { channel: 1, value: 0.5, lagSeconds: 0.25 }) "bus 13, gliding"
  ]
  where
  packet name message why = { name, message, why }

es9Refused :: Array Refused
es9Refused =
  [ refused "cv-bus-sixteen" (Osc.encodeUnchecked cv { bus: 16, value: 0.5 }) "bus-out-of-range" "buses are 0 to 15"
  , refused "cv-bus-negative" (Osc.encodeUnchecked cv { bus: -1, value: 0.5 }) "bus-out-of-range" "buses are 0 to 15"
  , refused "cv-not-a-number" (Osc.encodeUnchecked cv { bus: 8, value: nan }) "non-finite-value" "a NaN level"
  , refused "cv-trig-negative-length" (Osc.encodeUnchecked cvTrig { bus: 8, value: 0.5, durationMs: -1.0 }) "negative-time" "a length is not negative"
  , refused "cv-trig-at-negative-delay" (Osc.encodeUnchecked cvTrigAt { bus: 8, value: 0.5, durationMs: 10.0, delayMs: -1.0 }) "negative-time" "a delay is not negative"
  , refused "esx-slot-eight" (Osc.encodeUnchecked esx { slot: 8, value: 0.5 }) "out-of-range" "outputs are 0 to 7"
  , refused "esx5gate-state-two" (Osc.encodeUnchecked esx5Gate { bit: 3, state: 2 }) "not-a-flag" "1 or 0"
  , refused "cv-integer-level" (Osc.oscString "/cv" <> Osc.oscString ",ii" <> int32ToBytes 8 <> int32ToBytes 1) "wrong-type-tags" "an integer level is not what is declared; Architeuthis sent this until 2026-11-14"
  , refused "esx-integer-level" (Osc.oscString "/esx" <> Osc.oscString ",ii" <> int32ToBytes 3 <> int32ToBytes 0) "wrong-type-tags" "an integer level, as above"
  , refused "tidal-gate-trig-integer-length" (Osc.oscString "/tidal/gate/trig" <> Osc.oscString ",ii" <> int32ToBytes 2 <> int32ToBytes 10) "wrong-type-tags" "an integer length, as above"
  ]
    <> map (\testCase -> refused testCase.name testCase.bytes "" testCase.why) (Array.filter (\testCase -> testCase.expect == "refuse") toEs9Mechanical)
  where
  refused name bytes reason why = { name, bytes, reason, why }

-- | Nothing. Until 2026-11-14 Architeuthis's `Tidal/OSC.erl` chose each type
-- | tag from the Erlang value it was handed, so a whole-number level went out
-- | as an integer, and es9-daemon read any number for any argument.
-- | Architeuthis now sends through the descriptions, and those packets are
-- | in `es9Refused`.
es9Tolerated :: Array (Tolerated ToEs9)
es9Tolerated = []

es9Other :: Array Other
es9Other =
  [ { name: "empty", bytes: [], why: "nothing at all" }
  , { name: "an-anchor", bytes: anchorPacket, why: "another message of the rig's" }
  , { name: "unknown-cv-verb", bytes: Osc.oscString "/cv/ramp" <> Osc.oscString ",if", why: "an address es9-daemon does not read" }
  , { name: "a-tidal-prefix", bytes: Osc.oscString "/tidal" <> Osc.oscString ",", why: "a shorter address" }
  ]

-- ── The reference against the declared cases ───────────────────────────────

failures :: Array String
failures =
  pinned "note-at" (encodeToDiaphus <$> Array.head (map _.message diaphusPackets)) noteAtCanonicalHex
    <> pinned "clock-restart" (Just (encodeToDiaphus (ClockRestart {}))) clockRestartCanonicalHex
    <> pinned "cv" (encodeToEs9 <$> Array.head (map _.message es9Packets)) cvCanonicalHex
    <> wire "diaphus" encodeToDiaphus toDiaphusKinds diaphusPackets diaphusRefused diaphusTolerated diaphusOther
    <> wire "es9" encodeToEs9 toEs9Kinds es9Packets es9Refused es9Tolerated es9Other
    <> covered "diaphus" (map _.name toDiaphusKinds) (map (_.message >>> encodeToDiaphus) diaphusPackets)
    <> covered "es9" (map _.name toEs9Kinds) (map (_.message >>> encodeToEs9) es9Packets)
  where
  pinned label encoded expected = case encoded of
    Just (Right bytes) | hex bytes == expected -> []
    _ -> [ "daemons: the canonical " <> label <> " packet is not " <> expected ]

wire
  :: forall sum
   . Eq sum
  => String
  -> (sum -> Either String (Array Int))
  -> Array (Osc.Kind sum)
  -> Array (Packet sum)
  -> Array Refused
  -> Array (Tolerated sum)
  -> Array Other
  -> Array String
wire label encode kinds packets refused tolerated other =
  Array.concatMap packetFailures packets
    <> Array.concatMap refusedFailures refused
    <> Array.concatMap toleratedFailures tolerated
    <> Array.concatMap otherFailures other
    <> duplicates (map _.name packets <> map _.name refused <> map _.name other)
  where
  packetFailures testCase = case encode testCase.message of
    Left tag -> [ at testCase.name <> ": declared valid, the writer refuses it (" <> tag <> ")" ]
    Right bytes ->
      if Osc.decodeAny kinds bytes == Osc.Accept testCase.message then []
      else [ at testCase.name <> ": does not read back as what was written" ]
  refusedFailures testCase = case Osc.decodeAny kinds testCase.bytes of
    Osc.Refuse tag | testCase.reason == "" || testCase.reason == tag -> []
    Osc.Refuse tag -> [ at testCase.name <> ": declared " <> testCase.reason <> ", the reference says " <> tag ]
    arrival -> [ at testCase.name <> ": declared refused, the reference says " <> Osc.verdictName arrival ]
  -- A tolerated packet is one the reference refuses: if it accepted it,
  -- the packet would be declared, not tolerated.
  toleratedFailures testCase = case Osc.decodeAny kinds testCase.bytes, encode testCase.reads of
    Osc.Refuse _, Right _ -> []
    _, Left _ -> [ at testCase.name <> ": what it is read as is not itself valid" ]
    _, _ -> [ at testCase.name <> ": declared tolerated, but the reference does not refuse it" ]
  otherFailures testCase = case Osc.decodeAny kinds testCase.bytes of
    Osc.Other -> []
    arrival -> [ at testCase.name <> ": declared other, the reference says " <> Osc.verdictName arrival ]
  at name = label <> "/" <> name
  duplicates names =
    if Array.length (Array.nub names) == Array.length names then [] else [ label <> ": two cases share a name" ]

-- | Every described message appears in at least one packet.
covered :: String -> Array String -> Array (Either String (Array Int)) -> Array String
covered label addresses encoded =
  Array.filter (\address -> not (Array.elem address used)) addresses
    <#> \address -> label <> ": no packet exercises " <> address
  where
  used = Array.mapMaybe
    ( case _ of
        Right bytes -> Just (oscStringAt 0 bytes)
        Left _ -> Nothing
    )
    encoded

-- | The OSC string that starts at an offset.
oscStringAt :: Int -> Array Int -> String
oscStringAt offset bytes =
  fromCharArray (Array.mapMaybe fromCharCode (Array.takeWhile (_ /= 0) (Array.drop offset bytes)))

summary :: String
summary =
  show (Array.length diaphusPackets + Array.length es9Packets) <> " daemon packets, "
    <> show (Array.length diaphusRefused + Array.length es9Refused)
    <> " refused, "
    <> show (Array.length diaphusTolerated + Array.length es9Tolerated)
    <> " tolerated"

-- ── The vector files ───────────────────────────────────────────────────────

object :: Array (Tuple String Json) -> Json
object = Object.fromFoldable >>> Json.fromObject

text :: String -> String -> Tuple String Json
text key value = Tuple key (Json.fromString value)

vectors
  :: forall sum
   . String
  -> String
  -> (sum -> Either String (Array Int))
  -> (sum -> Array Json)
  -> Array (Osc.Kind sum)
  -> Array (Packet sum)
  -> Array Refused
  -> Array (Tolerated sum)
  -> Array Other
  -> Json
vectors version declaration encode values kinds packets refused tolerated other = object
  [ Tuple version (Json.fromNumber 1.0)
  , text "declaration" declaration
  , text "generatedBy" "Test.Daemons in binnacle; do not edit by hand, run `make vectors`"
  , Tuple "messages" $ Json.fromArray $ kinds <#> \kind -> object [ text "address" kind.name, text "tags" kind.tags ]
  , Tuple "packets" $ Json.fromArray $ packets <#> \testCase ->
      let
        bytes = fromMaybe [] (rightOf (encode testCase.message))
      in
        object
          [ text "name" testCase.name
          , text "why" testCase.why
          , text "address" (oscStringAt 0 bytes)
          , Tuple "values" (Json.fromArray (values testCase.message))
          , text "hex" (hex bytes)
          ]
  , Tuple "refused" $ Json.fromArray $ refused <#> \testCase -> object
      [ text "name" testCase.name
      , text "why" testCase.why
      , text "reason" (reasonOf (Osc.decodeAny kinds testCase.bytes))
      , text "hex" (hex testCase.bytes)
      ]
  , Tuple "tolerated" $ Json.fromArray $ tolerated <#> \testCase -> object
      [ text "name" testCase.name
      , text "why" testCase.why
      , text "address" (oscStringAt 0 testCase.bytes)
      , Tuple "values" (Json.fromArray (values testCase.reads))
      , text "hex" (hex testCase.bytes)
      ]
  , Tuple "other" $ Json.fromArray $ other <#> \testCase -> object
      [ text "name" testCase.name
      , text "why" testCase.why
      , text "hex" (hex testCase.bytes)
      ]
  ]
  where
  rightOf = case _ of
    Right value -> Just value
    Left _ -> Nothing
  reasonOf = case _ of
    Osc.Refuse tag -> tag
    _ -> ""

diaphusVectors :: Json
diaphusVectors = vectors "diaphus-inbound-vectors" "conformance/DIAPHUS-INBOUND.md" encodeToDiaphus valuesToDiaphus toDiaphusKinds diaphusPackets diaphusRefused diaphusTolerated diaphusOther

es9Vectors :: Json
es9Vectors = vectors "es9-osc-vectors" "conformance/ES9-OSC.md" encodeToEs9 valuesToEs9 toEs9Kinds es9Packets es9Refused es9Tolerated es9Other
