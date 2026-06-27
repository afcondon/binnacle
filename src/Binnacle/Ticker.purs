-- | A background-safe interval ticker, backed by a Web Worker.
-- |
-- | A main-thread `setInterval` is throttled to ≥1s once its tab is
-- | backgrounded (you switch to Ableton), which starves the lookahead
-- | scheduler and stalls MIDI. A Worker's timer keeps firing in the
-- | background, so we run the metronome tick THERE and `postMessage` back to
-- | the main thread, which still does the actual scheduling and Web-MIDI
-- | `send` (the Web MIDI API isn't available inside a worker, and `send` with
-- | a future timestamp fires precisely regardless of tab focus). This is the
-- | Web-Worker half of the "tale of two clocks" pattern — the worker is the
-- | jittery-but-alive metronome; the precise output clock stays on the main
-- | thread / in es9-daemon.
module Binnacle.Ticker
  ( startWorkerTicker
  ) where

import Prelude

import Effect (Effect)

-- | `startWorkerTicker tickMs onTick` fires `onTick` roughly every `tickMs`
-- | milliseconds from a Worker timer (which keeps running while the tab is
-- | backgrounded). Returns a canceller. Falls back to a main-thread
-- | `setInterval` (correct, just throttled in the background) where Workers
-- | or blob URLs are unavailable.
foreign import startWorkerTicker :: Int -> Effect Unit -> Effect (Effect Unit)
