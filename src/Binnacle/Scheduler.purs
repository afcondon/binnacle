-- | A lookahead grid scheduler. It walks a beat grid ~`lookaheadMs` ahead
-- | of the clock and calls `onTick` once per step, handing each step its
-- | exact fire-time. The app uses that to (a) schedule audio with a precise
-- | `delayMs` (es9-daemon fires it sample-accurately) and (b) animate its
-- | UI against the same timestamps — so visual and audio derive from one
-- | clock and stay locked together regardless of browser-timer jitter.
-- |
-- | This is the classic "tale of two clocks" pattern: a lazy, jittery JS
-- | timer drives a precise output clock (here, CoreAudio inside es9-daemon).
module Binnacle.Scheduler
  ( GridConfig
  , Tick
  , Canceller
  , startGrid
  ) where

import Prelude

import Data.Int (ceil, toNumber)
import Effect (Effect)
import Effect.Ref as Ref
import Effect.Timer (clearInterval, setInterval)
import Binnacle.Clock (Clock)
import Binnacle.Clock as Clock

type GridConfig =
  { stepBeats :: Number    -- musical length of one step (0.25 = a 16th)
  , lookaheadMs :: Number  -- schedule this far ahead (≈ 120)
  , tickMs :: Int          -- scheduler poll interval (≈ 25)
  }

type Tick =
  { index :: Int             -- monotonic step counter
  , beat :: Number           -- the beat this step lands on
  , fireUnixMicros :: Number  -- absolute wall-clock fire time
  , delayMs :: Number        -- delay from now until fire (for fire-at)
  }

type Canceller = Effect Unit

-- | Start the grid. Returns a canceller that stops the scheduler.
startGrid :: Clock -> GridConfig -> (Tick -> Effect Unit) -> Effect Canceller
startGrid clock cfg onTick = do
  -- Begin at the next whole step from "now" so we don't replay history.
  r0 <- Clock.read clock
  nextRef <- Ref.new (ceil (r0.beat / cfg.stepBeats))
  id <- setInterval cfg.tickMs do
    r <- Clock.read clock
    nowMicros <- Clock.unixMicrosNow clock
    -- Snap forward if we've fallen behind the clock. The clock JUMPS when it
    -- transitions from free-run to Link-lock (beat ~0 → the rig's live beat,
    -- which can be tens of thousands). Without this guard the recursive `drain`
    -- would replay every step across that gap and overflow the stack. A live
    -- sequencer must never play late notes anyway — skip the past, schedule
    -- only the lookahead window.
    let nowIdx = ceil (r.beat / cfg.stepBeats)
    behind <- Ref.read nextRef
    when (behind < nowIdx) (Ref.write nowIdx nextRef)
    let lookaheadBeats = cfg.lookaheadMs / 1000.0 * r.tempo / 60.0
        horizon = r.beat + lookaheadBeats
        drain = do
          idx <- Ref.read nextRef
          let stepBeat = toNumber idx * cfg.stepBeats
          when (stepBeat <= horizon) do
            fireMicros <- Clock.beatToUnixMicros clock stepBeat
            onTick
              { index: idx
              , beat: stepBeat
              , fireUnixMicros: fireMicros
              , delayMs: max 0.0 ((fireMicros - nowMicros) / 1000.0)
              }
            Ref.write (idx + 1) nextRef
            drain
    drain
  pure (clearInterval id)
