-- | Background-throttle defence beyond the Web Worker.
-- |
-- | A Web Worker's timer survives a backgrounded tab for a while, but Chrome's
-- | "intensive throttling" (after ~5 min) throttles background workers too, and
-- | macOS App Nap suspends the whole process. The fix browsers exempt from both
-- | is a tab that is *playing audio*: an active Web Audio context counts as
-- | audio activity (stops App Nap) and marks the tab audible (exempt from
-- | throttling). So we run one inaudible oscillator for the life of the page.
-- |
-- | AudioContext can't start without a user gesture (autoplay policy), so
-- | `armAudioKeepAlive` installs gesture listeners that create/resume it on the
-- | first interaction (and re-resume on any later one).
module Binnacle.Audio (armAudioKeepAlive) where

import Prelude

import Effect (Effect)

foreign import armAudioKeepAlive :: Effect Unit
