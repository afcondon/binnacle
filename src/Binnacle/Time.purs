-- | Two browser clocks. `perfNow` is the smooth monotonic clock for
-- | animation; `dateNow` is the wall clock that — on the rig host — reads
-- | the SAME time source link-spike stamps the anchor with, so host-time
-- | maps to browser-time with no NTP handshake (see Binnacle.Clock).
module Binnacle.Time
  ( perfNow
  , dateNow
  ) where

import Effect (Effect)

-- | `performance.now()` — high-resolution monotonic milliseconds since
-- | page load.
foreign import perfNow :: Effect Number

-- | `Date.now()` — wall-clock milliseconds since the Unix epoch.
foreign import dateNow :: Effect Number
