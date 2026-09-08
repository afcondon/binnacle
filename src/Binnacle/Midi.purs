-- | A Web MIDI output instrument. The browser opens a CoreMIDI output
-- | (e.g. an IAC bus into Ableton) and schedules notes with timestamps, so
-- | it's as jitter-immune as the es9 path — the lookahead scheduler's
-- | `delayMs` becomes a Web MIDI delivery timestamp. This is the
-- | rig-independent output: clock can still come from the rig (or free-run),
-- | but the sound goes straight to a DAW with no modular patching.
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

import Data.Maybe (Maybe)
import Data.Nullable (Nullable, toMaybe)
import Effect (Effect)
import Effect.Uncurried
  (EffectFn1, EffectFn2, EffectFn3, EffectFn4, EffectFn5, EffectFn6, mkEffectFn1, mkEffectFn3, runEffectFn1, runEffectFn2, runEffectFn4, runEffectFn5, runEffectFn6)

foreign import data MidiAccess :: Type
foreign import data MidiOut :: Type
foreign import data MidiIn :: Type

-- | One raw incoming MIDI message: the three bytes as ints. `status` is the full
-- | status byte (high nibble = kind — 0xB0 CC, 0x90 note-on, 0x80 note-off; low
-- | nibble = channel); `data1`/`data2` are controller/value or note/velocity.
-- | Decoding is left to the caller so one input path serves encoders, switches
-- | and pads without the FFI committing to a device layout.
type MidiMsg = { status :: Int, data1 :: Int, data2 :: Int }

foreign import requestAccessImpl :: EffectFn1 (EffectFn1 (Nullable MidiAccess) Unit) Unit
foreign import outputNamesImpl :: EffectFn1 MidiAccess (Array String)
foreign import findOutputImpl :: EffectFn2 MidiAccess String (Nullable MidiOut)
foreign import inputNamesImpl :: EffectFn1 MidiAccess (Array String)
foreign import findInputImpl :: EffectFn2 MidiAccess String (Nullable MidiIn)
foreign import onMessageImpl :: EffectFn2 MidiIn (EffectFn3 Int Int Int Unit) (Effect Unit)
foreign import scheduleNoteImpl :: EffectFn6 MidiOut Int Int Int Number Number Unit
foreign import sendCCImpl :: EffectFn4 MidiOut Int Int Int Unit
foreign import noteOnAtImpl :: EffectFn5 MidiOut Int Int Int Number Unit
foreign import noteOffAtImpl :: EffectFn4 MidiOut Int Int Number Unit
-- Absolute-timestamp variants: the last Number is an ABSOLUTE performance.now ms,
-- passed straight to Web MIDI's send (no fresh performance.now() at send time).
foreign import scheduleNoteAtMsImpl :: EffectFn6 MidiOut Int Int Int Number Number Unit
foreign import sendCCAtMsImpl :: EffectFn5 MidiOut Int Int Int Number Unit
foreign import noteOnAtMsImpl :: EffectFn5 MidiOut Int Int Int Number Unit
foreign import noteOffAtMsImpl :: EffectFn4 MidiOut Int Int Number Unit

-- | Request Web MIDI access. Calls back with `Nothing` if Web MIDI is
-- | unsupported or the user denies the permission prompt.
requestAccess :: (Maybe MidiAccess -> Effect Unit) -> Effect Unit
requestAccess k =
  runEffectFn1 requestAccessImpl (mkEffectFn1 \n -> k (toMaybe n))

-- | Names of every available MIDI output port (for diagnostics / picking).
outputNames :: MidiAccess -> Effect (Array String)
outputNames = runEffectFn1 outputNamesImpl

-- | First output port whose name contains `needle` (`""` = first port).
findOutput :: MidiAccess -> String -> Effect (Maybe MidiOut)
findOutput access needle = toMaybe <$> runEffectFn2 findOutputImpl access needle

-- | Names of every available MIDI input port (for diagnostics / picking).
inputNames :: MidiAccess -> Effect (Array String)
inputNames = runEffectFn1 inputNamesImpl

-- | First input port whose name contains `needle` (`""` = first port). This is
-- | how a control surface (MidiFighter Twister) is located to listen on.
findInput :: MidiAccess -> String -> Effect (Maybe MidiIn)
findInput access needle = toMaybe <$> runEffectFn2 findInputImpl access needle

-- | Subscribe to an input's messages. The handler runs on every incoming MIDI
-- | message; the returned Effect unsubscribes (clears `onmidimessage`). Store it
-- | and call it on teardown to avoid a leaked listener.
onMessage :: MidiIn -> (MidiMsg -> Effect Unit) -> Effect (Effect Unit)
onMessage inp k =
  runEffectFn2 onMessageImpl inp (mkEffectFn3 \status data1 data2 -> k { status, data1, data2 })

-- | Schedule a note: note-on at now + `delayMs`, note-off `durMs` later.
-- | `channel` is 0-based (0 → MIDI channel 1).
scheduleNote
  :: MidiOut
  -> { channel :: Int, note :: Int, velocity :: Int, delayMs :: Number, durMs :: Number }
  -> Effect Unit
scheduleNote out o =
  runEffectFn6 scheduleNoteImpl out o.channel o.note o.velocity o.delayMs o.durMs

-- | Send a control-change immediately. `channel` is 0-based. Used for glide
-- | (portamento on/off CC 65 + time CC 5) on the head's channel.
sendCC :: MidiOut -> { channel :: Int, controller :: Int, value :: Int } -> Effect Unit
sendCC out o = runEffectFn4 sendCCImpl out o.channel o.controller o.value

-- | A control change timestamped on the performance clock, not sent at call
-- | time. Needed wherever a CC must land a known interval BEFORE a note that is
-- | itself scheduled ahead — the Rample's start point being the case in hand:
-- | it selects which slice the next trigger plays, so arriving late plays the
-- | previous slice, which sounds like a wrong note rather than like a fault.
sendCCAtMs
  :: MidiOut
  -> { channel :: Int, controller :: Int, value :: Int, atMs :: Number }
  -> Effect Unit
sendCCAtMs out o =
  runEffectFn5 sendCCAtMsImpl out o.channel o.controller o.value o.atMs

-- | Note-on at now + `delayMs`, with no automatic note-off. The caller is
-- | responsible for the matching `noteOffAt` (legato / tie / glide).
noteOnAt :: MidiOut -> { channel :: Int, note :: Int, velocity :: Int, delayMs :: Number } -> Effect Unit
noteOnAt out o = runEffectFn5 noteOnAtImpl out o.channel o.note o.velocity o.delayMs

-- | Note-off at now + `delayMs`.
noteOffAt :: MidiOut -> { channel :: Int, note :: Int, delayMs :: Number } -> Effect Unit
noteOffAt out o = runEffectFn4 noteOffAtImpl out o.channel o.note o.delayMs

-- | Absolute-time variants — `atMs` is an ABSOLUTE `performance.now` millisecond
-- | timestamp (e.g. from `Clock.perfMsAt`). Web MIDI fires at that instant
-- | regardless of when `send` runs, so latency between deciding the time and
-- | sending isn't added on top (fixes the ~130 ms frontend co-sim offset). A past
-- | `atMs` fires immediately, so 0.0 still means "now".
scheduleNoteAtMs
  :: MidiOut
  -> { channel :: Int, note :: Int, velocity :: Int, atMs :: Number, durMs :: Number }
  -> Effect Unit
scheduleNoteAtMs out o =
  runEffectFn6 scheduleNoteAtMsImpl out o.channel o.note o.velocity o.atMs o.durMs

noteOnAtMs :: MidiOut -> { channel :: Int, note :: Int, velocity :: Int, atMs :: Number } -> Effect Unit
noteOnAtMs out o = runEffectFn5 noteOnAtMsImpl out o.channel o.note o.velocity o.atMs

noteOffAtMs :: MidiOut -> { channel :: Int, note :: Int, atMs :: Number } -> Effect Unit
noteOffAtMs out o = runEffectFn4 noteOffAtMsImpl out o.channel o.note o.atMs
