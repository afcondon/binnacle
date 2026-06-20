-- | A Web MIDI output instrument. The browser opens a CoreMIDI output
-- | (e.g. an IAC bus into Ableton) and schedules notes with timestamps, so
-- | it's as jitter-immune as the es9 path — the lookahead scheduler's
-- | `delayMs` becomes a Web MIDI delivery timestamp. This is the
-- | rig-independent output: clock can still come from the rig (or free-run),
-- | but the sound goes straight to a DAW with no modular patching.
module Binnacle.Midi
  ( MidiAccess
  , MidiOut
  , requestAccess
  , outputNames
  , findOutput
  , scheduleNote
  ) where

import Prelude

import Data.Maybe (Maybe)
import Data.Nullable (Nullable, toMaybe)
import Effect (Effect)
import Effect.Uncurried
  (EffectFn1, EffectFn2, EffectFn6, mkEffectFn1, runEffectFn1, runEffectFn2, runEffectFn6)

foreign import data MidiAccess :: Type
foreign import data MidiOut :: Type

foreign import requestAccessImpl :: EffectFn1 (EffectFn1 (Nullable MidiAccess) Unit) Unit
foreign import outputNamesImpl :: EffectFn1 MidiAccess (Array String)
foreign import findOutputImpl :: EffectFn2 MidiAccess String (Nullable MidiOut)
foreign import scheduleNoteImpl :: EffectFn6 MidiOut Int Int Int Number Number Unit

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

-- | Schedule a note: note-on at now + `delayMs`, note-off `durMs` later.
-- | `channel` is 0-based (0 → MIDI channel 1).
scheduleNote
  :: MidiOut
  -> { channel :: Int, note :: Int, velocity :: Int, delayMs :: Number, durMs :: Number }
  -> Effect Unit
scheduleNote out o =
  runEffectFn6 scheduleNoteImpl out o.channel o.note o.velocity o.delayMs o.durMs
