-- | The REFERENCE for the OSC that the two Rust daemons read: Diaphus on
-- | UDP 57122 and es9-daemon on UDP 57130. The declarations are
-- | `conformance/DIAPHUS-INBOUND.md` and `conformance/ES9-OSC.md`; their
-- | vectors are generated from here by `make vectors`.
-- |
-- | This is its own package (`rig-wires`) so that a writer can send through
-- | these descriptions and not through an encoder of its own. Architeuthis
-- | does, on the BEAM. Binnacle's tests take it for the vectors.
-- |
-- | Each message is described once with Hawser, as its WRITERS produce it
-- | (surveyed 2026-11-13: Erlang, Go, Rust, JavaScript and Python senders).
-- | The two sum types are written by hand over the descriptions.
module Wires.Daemons
  ( ToDiaphus(..)
  , ToEs9(..)
  , NoteAt
  , NoteOnAt
  , NoteOffAt
  , ControlAt
  , Cv
  , CvSlew
  , CvTrig
  , CvTrigAt
  , encodeToDiaphus
  , encodeToEs9
  , valuesToDiaphus
  , valuesToEs9
  , toDiaphusKinds
  , toEs9Kinds
  , toDiaphusMechanical
  , toEs9Mechanical
  , noteAt
  , noteOnAt
  , noteOffAt
  , controlAt
  , setTempo
  , play
  , clockRestart
  , cv
  , cvSlew
  , cvTrig
  , cvTrigAt
  , esx
  , esxEnable
  , esx5Gate
  , tidalGate
  , tidalGateTrig
  , tidalCv
  , tidalCvSlew
  , diaphusTable
  , es9Table
  ) where

import Prelude

import Data.Argonaut.Core (Json)
import Data.Either (Either)
import Hawser.Document as Document
import Hawser.Message (Message, field, message)
import Hawser.Osc as Osc
import Hawser.Value (Value, within, finite, float32, int64, notNegative, number, string, whole)

-- ── Fields the two wires share ─────────────────────────────────────────────

-- | A MIDI channel as musicians count them.
channel :: Value Int
channel = within "channel-out-of-range" 1 16 whole

sevenBit :: Value Int
sevenBit = within "not-seven-bit" 0 127 whole

-- | A moment: microseconds since the Unix epoch, as in `/link/anchor`.
moment :: Value Number
moment = notNegative 0.0 "time-before-epoch" int64

flag :: Value Int
flag = within "not-a-flag" 0 1 whole

-- | One of the ES-9's sixteen output buses.
bus :: Value Int
bus = within "bus-out-of-range" 0 15 whole

eighth :: Value Int
eighth = within "out-of-range" 0 7 whole

-- | A level, where 1.0 is full scale. Sent as a binary32.
level :: Value Number
level = finite float32

-- | A length of time that cannot be negative. Sent as a binary32.
span :: Value Number
span = notNegative 0.0 "negative-time" (finite float32)

-- ── To Diaphus ─────────────────────────────────────────────────────────────

type NoteAt = { port :: String, channel :: Int, note :: Int, velocity :: Int, durationMs :: Int, unixMicros :: Number }
type NoteOnAt = { port :: String, channel :: Int, note :: Int, velocity :: Int, unixMicros :: Number }
type NoteOffAt = { port :: String, channel :: Int, note :: Int, unixMicros :: Number }
type ControlAt = { port :: String, channel :: Int, controller :: Int, value :: Int, unixMicros :: Number }

noteAt :: Message NoteAt
noteAt = message "/midi/note/at" "A note of a given length, at a moment." $
  { port: _, channel: _, note: _, velocity: _, durationMs: _, unixMicros: _ }
    <$> field "port" _.port string "the MIDI destination, by name"
    <*> field "channel" _.channel channel "the MIDI channel"
    <*> field "note" _.note sevenBit "the note number"
    <*> field "velocity" _.velocity sevenBit "the velocity"
    <*> field "durationMs" _.durationMs (notNegative 0 "negative-duration" whole) "how long until the note-off"
    <*> field "unixMicros" _.unixMicros moment "when the note-on is due"

noteOnAt :: Message NoteOnAt
noteOnAt = message "/midi/on/at" "A note-on alone, at a moment." $
  { port: _, channel: _, note: _, velocity: _, unixMicros: _ }
    <$> field "port" _.port string "the MIDI destination, by name"
    <*> field "channel" _.channel channel "the MIDI channel"
    <*> field "note" _.note sevenBit "the note number"
    <*> field "velocity" _.velocity sevenBit "the velocity"
    <*> field "unixMicros" _.unixMicros moment "when it is due"

noteOffAt :: Message NoteOffAt
noteOffAt = message "/midi/off/at" "A note-off alone, at a moment." $
  { port: _, channel: _, note: _, unixMicros: _ }
    <$> field "port" _.port string "the MIDI destination, by name"
    <*> field "channel" _.channel channel "the MIDI channel"
    <*> field "note" _.note sevenBit "the note number"
    <*> field "unixMicros" _.unixMicros moment "when it is due"

controlAt :: Message ControlAt
controlAt = message "/midi/cc/at" "A control change, at a moment." $
  { port: _, channel: _, controller: _, value: _, unixMicros: _ }
    <$> field "port" _.port string "the MIDI destination, by name"
    <*> field "channel" _.channel channel "the MIDI channel"
    <*> field "controller" _.controller sevenBit "the controller number"
    <*> field "value" _.value sevenBit "its value"
    <*> field "unixMicros" _.unixMicros moment "when it is due"

setTempo :: Message { bpm :: Number }
setTempo = message "/link/set-tempo" "Set the Link session's tempo, for every peer." $
  { bpm: _ } <$> field "bpm" _.bpm (within "tempo-out-of-range" 20.0 999.0 (finite number)) "beats per minute"

play :: Message { on :: Int }
play = message "/link/play" "Start the session's transport on the next bar line, or stop it now." $
  { on: _ } <$> field "on" _.on flag "1 to start, 0 to stop"

clockRestart :: Message {}
clockRestart = message "/clock/restart" "Start every clocked port again on the next bar line." (pure {})

data ToDiaphus
  = NoteAt NoteAt
  | NoteOnAt NoteOnAt
  | NoteOffAt NoteOffAt
  | ControlAt ControlAt
  | SetTempo { bpm :: Number }
  | Play { on :: Int }
  | ClockRestart {}

derive instance Eq ToDiaphus

-- | Total, so a constructor without a description does not compile. The
-- | `Left` is the tag of the rule the value breaks.
encodeToDiaphus :: ToDiaphus -> Either String (Array Int)
encodeToDiaphus = case _ of
  NoteAt m -> Osc.encode noteAt m
  NoteOnAt m -> Osc.encode noteOnAt m
  NoteOffAt m -> Osc.encode noteOffAt m
  ControlAt m -> Osc.encode controlAt m
  SetTempo m -> Osc.encode setTempo m
  Play m -> Osc.encode play m
  ClockRestart m -> Osc.encode clockRestart m

-- | The arguments in order, for the vector file.
valuesToDiaphus :: ToDiaphus -> Array Json
valuesToDiaphus = case _ of
  NoteAt m -> Osc.values noteAt m
  NoteOnAt m -> Osc.values noteOnAt m
  NoteOffAt m -> Osc.values noteOffAt m
  ControlAt m -> Osc.values controlAt m
  SetTempo m -> Osc.values setTempo m
  Play m -> Osc.values play m
  ClockRestart m -> Osc.values clockRestart m

toDiaphusKinds :: Array (Osc.Kind ToDiaphus)
toDiaphusKinds =
  [ Osc.kind noteAt NoteAt
  , Osc.kind noteOnAt NoteOnAt
  , Osc.kind noteOffAt NoteOffAt
  , Osc.kind controlAt ControlAt
  , Osc.kind setTempo SetTempo
  , Osc.kind play Play
  , Osc.kind clockRestart ClockRestart
  ]

iac :: String
iac = "IAC Driver Tidal"

-- | 2026-11-10 16:00:00 UTC, as in the anchor's canonical case.
then_ :: Number
then_ = 1794326400000000.0

toDiaphusMechanical :: Array Osc.Case
toDiaphusMechanical =
  prefixed "note-at" (Osc.mechanical noteAt { port: iac, channel: 1, note: 60, velocity: 100, durationMs: 250, unixMicros: then_ })
    <> prefixed "note-on-at" (Osc.mechanical noteOnAt { port: iac, channel: 1, note: 60, velocity: 100, unixMicros: then_ })
    <> prefixed "note-off-at" (Osc.mechanical noteOffAt { port: iac, channel: 1, note: 60, unixMicros: then_ })
    <> prefixed "cc-at" (Osc.mechanical controlAt { port: iac, channel: 1, controller: 7, value: 100, unixMicros: then_ })
    <> prefixed "set-tempo" (Osc.mechanical setTempo { bpm: 120.0 })
    <> prefixed "play" (Osc.mechanical play { on: 1 })

prefixed :: String -> Array Osc.Case -> Array Osc.Case
prefixed prefix = map \testCase -> testCase { name = prefix <> "-" <> testCase.name }

-- ── To es9-daemon ──────────────────────────────────────────────────────────

type Cv = { bus :: Int, value :: Number }
type CvSlew = { bus :: Int, value :: Number, lagSeconds :: Number }
type CvTrig = { bus :: Int, value :: Number, durationMs :: Number }
type CvTrigAt = { bus :: Int, value :: Number, durationMs :: Number, delayMs :: Number }

cv :: Message Cv
cv = message "/cv" "Set a bus to a level and hold it." $
  { bus: _, value: _ }
    <$> field "bus" _.bus bus "the ES-9 bus"
    <*> field "value" _.value level "the level; 1.0 is 10 V"

cvSlew :: Message CvSlew
cvSlew = message "/cv/slew" "Glide a bus to a level." $
  { bus: _, value: _, lagSeconds: _ }
    <$> field "bus" _.bus bus "the ES-9 bus"
    <*> field "value" _.value level "the level to reach"
    <*> field "lagSeconds" _.lagSeconds span "the glide's time constant"

cvTrig :: Message CvTrig
cvTrig = message "/cv/trig" "Set a bus to a level now, and back to zero after a time." $
  { bus: _, value: _, durationMs: _ }
    <$> field "bus" _.bus bus "the ES-9 bus"
    <*> field "value" _.value level "the level while high"
    <*> field "durationMs" _.durationMs span "how long it stays high"

cvTrigAt :: Message CvTrigAt
cvTrigAt = message "/cv/trig/at" "As `/cv/trig`, starting a given time after arrival, to the sample." $
  { bus: _, value: _, durationMs: _, delayMs: _ }
    <$> field "bus" _.bus bus "the ES-9 bus"
    <*> field "value" _.value level "the level while high"
    <*> field "durationMs" _.durationMs span "how long it stays high"
    <*> field "delayMs" _.delayMs span "how long after arrival it starts"

esx :: Message { slot :: Int, value :: Number }
esx = message "/esx" "Set one ESX-8CV output. Turns the ES-5 encoding on." $
  { slot: _, value: _ }
    <$> field "slot" _.slot eighth "the ESX-8CV output"
    <*> field "value" _.value level "the level; 1.0 is full scale"

esxEnable :: Message { on :: Int }
esxEnable = message "/esx/enable" "Turn the ES-5 encoding on or off. Nothing on the rig sends this." $
  { on: _ } <$> field "on" _.on flag "1 for on, 0 for off"

esx5Gate :: Message { bit :: Int, state :: Int }
esx5Gate = message "/esx5gate" "Set one of the ES-5's own gates. Turns the ES-5 encoding on." $
  { bit: _, state: _ }
    <$> field "bit" _.bit eighth "the gate"
    <*> field "state" _.state flag "1 for high, 0 for low"

tidalGate :: Message { channel :: Int, state :: Int }
tidalGate = message "/tidal/gate" "Set a gate bus (8 to 15) by its index. Nothing on the rig sends this." $
  { channel: _, state: _ }
    <$> field "channel" _.channel eighth "the gate; bus 8 plus this"
    <*> field "state" _.state flag "1 for high, 0 for low"

tidalGateTrig :: Message { channel :: Int, durationMs :: Number }
tidalGateTrig = message "/tidal/gate/trig" "Raise a gate bus by its index for a time." $
  { channel: _, durationMs: _ }
    <$> field "channel" _.channel eighth "the gate; bus 8 plus this"
    <*> field "durationMs" _.durationMs span "how long it stays high"

tidalCv :: Message { channel :: Int, value :: Number }
tidalCv = message "/tidal/cv" "Set a CV bus (12 to 15) by its index, at half scale. Nothing on the rig sends this." $
  { channel: _, value: _ }
    <$> field "channel" _.channel (within "out-of-range" 0 3 whole) "the CV; bus 12 plus this"
    <*> field "value" _.value level "the level, which the daemon halves"

tidalCvSlew :: Message { channel :: Int, value :: Number, lagSeconds :: Number }
tidalCvSlew = message "/tidal/cv/slew" "Glide a CV bus by its index, at half scale. Nothing on the rig sends this." $
  { channel: _, value: _, lagSeconds: _ }
    <$> field "channel" _.channel (within "out-of-range" 0 3 whole) "the CV; bus 12 plus this"
    <*> field "value" _.value level "the level, which the daemon halves"
    <*> field "lagSeconds" _.lagSeconds span "the glide's time constant"

data ToEs9
  = Cv Cv
  | CvSlew CvSlew
  | CvTrig CvTrig
  | CvTrigAt CvTrigAt
  | Esx { slot :: Int, value :: Number }
  | EsxEnable { on :: Int }
  | Esx5Gate { bit :: Int, state :: Int }
  | TidalGate { channel :: Int, state :: Int }
  | TidalGateTrig { channel :: Int, durationMs :: Number }
  | TidalCv { channel :: Int, value :: Number }
  | TidalCvSlew { channel :: Int, value :: Number, lagSeconds :: Number }

derive instance Eq ToEs9

encodeToEs9 :: ToEs9 -> Either String (Array Int)
encodeToEs9 = case _ of
  Cv m -> Osc.encode cv m
  CvSlew m -> Osc.encode cvSlew m
  CvTrig m -> Osc.encode cvTrig m
  CvTrigAt m -> Osc.encode cvTrigAt m
  Esx m -> Osc.encode esx m
  EsxEnable m -> Osc.encode esxEnable m
  Esx5Gate m -> Osc.encode esx5Gate m
  TidalGate m -> Osc.encode tidalGate m
  TidalGateTrig m -> Osc.encode tidalGateTrig m
  TidalCv m -> Osc.encode tidalCv m
  TidalCvSlew m -> Osc.encode tidalCvSlew m

valuesToEs9 :: ToEs9 -> Array Json
valuesToEs9 = case _ of
  Cv m -> Osc.values cv m
  CvSlew m -> Osc.values cvSlew m
  CvTrig m -> Osc.values cvTrig m
  CvTrigAt m -> Osc.values cvTrigAt m
  Esx m -> Osc.values esx m
  EsxEnable m -> Osc.values esxEnable m
  Esx5Gate m -> Osc.values esx5Gate m
  TidalGate m -> Osc.values tidalGate m
  TidalGateTrig m -> Osc.values tidalGateTrig m
  TidalCv m -> Osc.values tidalCv m
  TidalCvSlew m -> Osc.values tidalCvSlew m

-- | Longer addresses first, so that `/cv/trig/at` is not taken for `/cv`
-- | with something after it. (It would not be: an address ends in a NUL.
-- | The order is for the reader of this list.)
toEs9Kinds :: Array (Osc.Kind ToEs9)
toEs9Kinds =
  [ Osc.kind cv Cv
  , Osc.kind cvSlew CvSlew
  , Osc.kind cvTrig CvTrig
  , Osc.kind cvTrigAt CvTrigAt
  , Osc.kind esx Esx
  , Osc.kind esx5Gate Esx5Gate
  , Osc.kind esxEnable EsxEnable
  , Osc.kind tidalGateTrig TidalGateTrig
  , Osc.kind tidalGate TidalGate
  , Osc.kind tidalCv TidalCv
  , Osc.kind tidalCvSlew TidalCvSlew
  ]

toEs9Mechanical :: Array Osc.Case
toEs9Mechanical =
  prefixed "cv" (Osc.mechanical cv { bus: 8, value: 0.5 })
    <> prefixed "cv-slew" (Osc.mechanical cvSlew { bus: 8, value: 0.5, lagSeconds: 0.25 })
    <> prefixed "cv-trig" (Osc.mechanical cvTrig { bus: 8, value: 0.5, durationMs: 10.0 })
    <> prefixed "cv-trig-at" (Osc.mechanical cvTrigAt { bus: 8, value: 0.5, durationMs: 10.0, delayMs: 62.5 })
    <> prefixed "esx" (Osc.mechanical esx { slot: 3, value: 0.5 })
    <> prefixed "esx5gate" (Osc.mechanical esx5Gate { bit: 3, state: 1 })
    <> prefixed "tidal-gate-trig" (Osc.mechanical tidalGateTrig { channel: 2, durationMs: 10.0 })

-- ── The declarations' tables ───────────────────────────────────────────────

-- | A row with the type tags beside the address.
tagged :: forall sum. Osc.Kind sum -> String
tagged kind = "| `" <> kind.name <> "` | `," <> kind.tags <> "` " <> dropName kind.row
  where
  -- A kind's row begins "| `address` "; the rest is its fields and meaning.
  dropName row = Document.afterFirstCell row

diaphusTable :: String
diaphusTable = Document.tableWith [ "Address", "Tags", "Arguments, in order", "Meaning" ] (map tagged toDiaphusKinds)

es9Table :: String
es9Table = Document.tableWith [ "Address", "Tags", "Arguments, in order", "Meaning" ] (map tagged toEs9Kinds)
