-- | The output instruments: schedule sample-accurate gates and set CV on
-- | es9-daemon buses, plus a 1V/oct note→volts helper. These format the
-- | Atlantis Sync Protocol's client→server verbs and send them over the
-- | transport; the rig relays them as OSC to es9-daemon.
module Binnacle.Output
  ( Tuning(..)
  , defaultTuning
  , voct
  , fireAt
  , cvOut
  , cvSlew
  , clockSubscribe
  ) where

import Prelude

import Data.Int (toNumber)
import Data.Number.Format (fixed, toStringWith)
import Effect (Effect)
import Binnacle.Transport (Socket, send)

-- | How MIDI notes map to es9 normalized CV. es9 takes −1.0..+1.0 as
-- | ±10 V, so 1 V/oct ⇒ 0.1 units/octave ⇒ 0.1/12 per semitone, with
-- | `refNote` sitting at 0 V.
newtype Tuning = Tuning
  { refNote :: Int
  , unitsPerSemitone :: Number
  }

defaultTuning :: Tuning
defaultTuning = Tuning { refNote: 60, unitsPerSemitone: 0.1 / 12.0 }

-- | MIDI note → normalized es9 CV value.
voct :: Tuning -> Int -> Number
voct (Tuning t) note = toNumber (note - t.refNote) * t.unitsPerSemitone

-- Fixed decimals so Erlang's binary_to_float always parses (no bare
-- integers, no scientific notation).
num :: Number -> String
num = toStringWith (fixed 5)

-- | Schedule a sample-accurate gate/trigger: bus held at `value` for
-- | `durMs`, firing `delayMs` from now.
fireAt
  :: Socket
  -> { bus :: Int, value :: Number, durMs :: Number, delayMs :: Number }
  -> Effect Unit
fireAt sock o =
  send sock $ "fire-at " <> show o.bus <> " " <> num o.value
    <> " " <> num o.durMs <> " " <> num o.delayMs

-- | Set a CV bus immediately (e.g. pitch ahead of a gate).
cvOut :: Socket -> { bus :: Int, value :: Number } -> Effect Unit
cvOut sock o = send sock $ "cv-out " <> show o.bus <> " " <> num o.value

-- | Set a CV bus with a slew/glide of `lagSec`.
cvSlew :: Socket -> { bus :: Int, value :: Number, lagSec :: Number } -> Effect Unit
cvSlew sock o =
  send sock $ "cv-slew " <> show o.bus <> " " <> num o.value <> " " <> num o.lagSec

-- | Ask the rig to start forwarding Link anchors to this connection.
clockSubscribe :: Socket -> Effect Unit
clockSubscribe sock = send sock "clock-subscribe"
