-- | A Web MIDI output instrument. The browser opens a CoreMIDI output
-- | (e.g. an IAC bus into Ableton) and schedules notes with timestamps, so
-- | it's as jitter-immune as the es9 path — the lookahead scheduler's
-- | `delayMs` becomes a Web MIDI delivery timestamp. This is the
-- | rig-independent output: clock can still come from the rig (or free-run),
-- | but the sound goes straight to a DAW with no modular patching.
-- |
-- | **The Web MIDI underneath is Helm's** (`Helm.WebMIDI`, music/helm): one
-- | FFI for every app on a controller, carrying the port-id and dedupe fixes
-- | this one lacked. This module keeps Binnacle's own shape on top of it —
-- | 0-based channels, delays and absolute timestamps — so its callers do not
-- | change.
module Binnacle.Midi
  ( MidiAccess
  , MidiOut
  , MidiIn
  , MidiMsg
  , requestAccess
  , outputNames
  , findOutput
  , inputNames
  , findInput
  , onMessage
  , scheduleNote
  , sendCC
  , noteOnAt
  , noteOffAt
  , scheduleNoteAtMs
  , sendCCAtMs
  , noteOnAtMs
  , noteOffAtMs
  ) where

import Prelude

import Data.Array (index)
import Data.Either (hush)
import Data.Int.Bits (and, or)
import Data.Maybe (Maybe, fromMaybe)
import Effect (Effect)
import Helm.WebMIDI as W

type MidiAccess = W.MIDIAccess
type MidiOut = W.MIDIOutput
type MidiIn = W.MIDIInput

-- | One raw incoming MIDI message: the three bytes as ints. `status` is the full
-- | status byte (high nibble = kind — 0xB0 CC, 0x90 note-on, 0x80 note-off; low
-- | nibble = channel); `data1`/`data2` are controller/value or note/velocity.
-- | Decoding is left to the caller so one input path serves encoders, switches
-- | and pads without the FFI committing to a device layout. A short message
-- | yields 0s for the missing bytes.
type MidiMsg = { status :: Int, data1 :: Int, data2 :: Int }

-- | Request Web MIDI access. Calls back with `Nothing` if Web MIDI is
-- | unsupported or the user denies the permission prompt.
requestAccess :: (Maybe MidiAccess -> Effect Unit) -> Effect Unit
requestAccess k = W.requestAccess { sysex: false } (k <<< hush)

-- | Names of every available MIDI output port (for diagnostics / picking).
outputNames :: MidiAccess -> Effect (Array String)
outputNames access = map _.name <$> W.outputs access

-- | First output port whose name contains `needle` (`""` = first port).
findOutput :: MidiAccess -> String -> Effect (Maybe MidiOut)
findOutput access needle = W.findOutput access (W.NameContains needle)

-- | Names of every available MIDI input port (for diagnostics / picking).
inputNames :: MidiAccess -> Effect (Array String)
inputNames access = map _.name <$> W.inputs access

-- | First input port whose name contains `needle` (`""` = first port). This is
-- | how a control surface (MidiFighter Twister) is located to listen on.
findInput :: MidiAccess -> String -> Effect (Maybe MidiIn)
findInput access needle = W.findInput access (W.NameContains needle)

-- | Subscribe to an input's messages. The handler runs on every incoming MIDI
-- | message; the returned Effect unsubscribes, and only ever removes its own
-- | handler. Store it and call it on teardown to avoid a leaked listener.
onMessage :: MidiIn -> (MidiMsg -> Effect Unit) -> Effect (Effect Unit)
onMessage inp k = W.onMessage inp \bytes ->
  let byte i = fromMaybe 0 (index bytes i)
  in k { status: byte 0, data1: byte 1, data2: byte 2 }

-- 0-based channel, masked as the old FFI masked it.
statusOf :: Int -> Int -> Int
statusOf kind channel = or kind (and channel 0x0F)

data7 :: Int -> Int
data7 n = and n 0x7F

on :: Int -> Int -> Int -> Array Int
on channel note velocity = [ statusOf 0x90 channel, data7 note, data7 velocity ]

off :: Int -> Int -> Array Int
off channel note = [ statusOf 0x80 channel, data7 note, 0 ]

cc :: Int -> Int -> Int -> Array Int
cc channel controller value = [ statusOf 0xB0 channel, data7 controller, data7 value ]

-- | A delay from now, as an absolute time on the performance clock.
fromNow :: Number -> Effect Number
fromNow delayMs = (_ + max 0.0 delayMs) <$> W.now

-- | Schedule a note: note-on at now + `delayMs`, note-off `durMs` later.
-- | `channel` is 0-based (0 → MIDI channel 1).
scheduleNote
  :: MidiOut
  -> { channel :: Int, note :: Int, velocity :: Int, delayMs :: Number, durMs :: Number }
  -> Effect Unit
scheduleNote out o = do
  atMs <- fromNow o.delayMs
  scheduleNoteAtMs out { channel: o.channel, note: o.note, velocity: o.velocity, atMs, durMs: o.durMs }

-- | Send a control-change immediately. `channel` is 0-based. Used for glide
-- | (portamento on/off CC 65 + time CC 5) on the head's channel.
sendCC :: MidiOut -> { channel :: Int, controller :: Int, value :: Int } -> Effect Unit
sendCC out o = W.send out (cc o.channel o.controller o.value)

-- | A control change timestamped on the performance clock, not sent at call
-- | time. Needed wherever a CC must land a known interval BEFORE a note that is
-- | itself scheduled ahead — the Rample's start point being the case in hand:
-- | it selects which slice the next trigger plays, so arriving late plays the
-- | previous slice, which sounds like a wrong note rather than like a fault.
sendCCAtMs
  :: MidiOut
  -> { channel :: Int, controller :: Int, value :: Int, atMs :: Number }
  -> Effect Unit
sendCCAtMs out o = W.sendAt out o.atMs (cc o.channel o.controller o.value)

-- | Note-on at now + `delayMs`, with no automatic note-off. The caller is
-- | responsible for the matching `noteOffAt` (legato / tie / glide).
noteOnAt :: MidiOut -> { channel :: Int, note :: Int, velocity :: Int, delayMs :: Number } -> Effect Unit
noteOnAt out o = do
  atMs <- fromNow o.delayMs
  W.sendAt out atMs (on o.channel o.note o.velocity)

-- | Note-off at now + `delayMs`.
noteOffAt :: MidiOut -> { channel :: Int, note :: Int, delayMs :: Number } -> Effect Unit
noteOffAt out o = do
  atMs <- fromNow o.delayMs
  W.sendAt out atMs (off o.channel o.note)

-- | Absolute-time variants — `atMs` is an ABSOLUTE `performance.now` millisecond
-- | timestamp (e.g. from `Clock.perfMsAt`). Web MIDI fires at that instant
-- | regardless of when `send` runs, so latency between deciding the time and
-- | sending isn't added on top (fixes the ~130 ms frontend co-sim offset). A past
-- | `atMs` fires immediately, so 0.0 still means "now".
scheduleNoteAtMs
  :: MidiOut
  -> { channel :: Int, note :: Int, velocity :: Int, atMs :: Number, durMs :: Number }
  -> Effect Unit
scheduleNoteAtMs out o = do
  W.sendAt out o.atMs (on o.channel o.note o.velocity)
  W.sendAt out (o.atMs + max 1.0 o.durMs) (off o.channel o.note)

noteOnAtMs :: MidiOut -> { channel :: Int, note :: Int, velocity :: Int, atMs :: Number } -> Effect Unit
noteOnAtMs out o = W.sendAt out o.atMs (on o.channel o.note o.velocity)

noteOffAtMs :: MidiOut -> { channel :: Int, note :: Int, atMs :: Number } -> Effect Unit
noteOffAtMs out o = W.sendAt out o.atMs (off o.channel o.note)
