-- | The chronometer. One clock that free-runs at a fallback tempo until
-- | the rig's Link anchor arrives, then phase-locks to it. The app always
-- | just reads `beat`/`bar`/`phase`; whether it's `locked` depends only on
-- | whether the rig is forwarding an anchor — so the same code path is the
-- | solo (free-run) and ensemble (Link-locked) story at once.
-- |
-- | An anchor is an affine map (unixMicros, beat, tempo, quantum):
-- |   beat(t) = beat + (t − unixMicros) · tempo / 60e6
-- | The browser maps host-time to its own clock via Date.now() (same wall
-- | clock as link-spike on the rig host), so no NTP handshake is needed.
module Binnacle.Clock
  ( Anchor(..)
  , Clock
  , ClockReading
  , newClock
  , ingestAnchor
  , setFreeBaseline
  , parseAnchorLine
  , read
  , unixMicrosNow
  , beatToUnixMicros
  , perfMsAt
  ) where

import Prelude

import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.String (Pattern(..))
import Data.String as String
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Binnacle.Time (dateNow, perfNow)

-- | The Link affine map as forwarded by the rig.
newtype Anchor = Anchor
  { unixMicros :: Number
  , beat :: Number
  , tempo :: Number
  , quantum :: Number
  }

type ClockState =
  { anchor :: Maybe Anchor
  , anchorPerf :: Number          -- perfNow at last anchor (for staleness)
  , epochOffsetMicros :: Number   -- unixMicros corresponding to perfNow = 0
  , freeTempo :: Number
  , freeQuantum :: Number
  , freeStartMicros :: Number      -- unixMicros at which free-run beat = 0
  , anchorCount :: Int             -- anchors ingested (diagnostic heartbeat)
  }

newtype Clock = Clock (Ref ClockState)

-- | An anchor older than this (no fresh packet) drops us back to free-run.
-- | link-spike publishes at 10 Hz, so 2 s ≈ 20 missed packets.
staleMs :: Number
staleMs = 2000.0

type ClockReading =
  { beat :: Number     -- absolute Link beats since beat 0
  , bar :: Int         -- floor(beat / quantum)
  , phase :: Number    -- beats within the current bar, [0, quantum)
  , tempo :: Number    -- BPM
  , quantum :: Number  -- beats per bar
  , locked :: Boolean  -- true once a fresh anchor is driving the clock
  , anchorCount :: Int -- total anchors ingested (climbs while the rig feeds us)
  }

-- | Construct a clock. Measures the wall-clock↔monotonic offset once and
-- | starts free-running at `tempo` until the first anchor arrives.
newClock :: { tempo :: Number } -> Effect Clock
newClock cfg = do
  d <- dateNow
  p <- perfNow
  let offset = (d - p) * 1000.0
  ref <- Ref.new
    { anchor: Nothing
    , anchorPerf: 0.0
    , epochOffsetMicros: offset
    , freeTempo: cfg.tempo
    , freeQuantum: 4.0
    , freeStartMicros: d * 1000.0
    , anchorCount: 0
    }
  pure (Clock ref)

-- | Current wall-clock time in microseconds (browser-mapped).
unixMicrosNow :: Clock -> Effect Number
unixMicrosNow (Clock ref) = do
  st <- Ref.read ref
  p <- perfNow
  pure (p * 1000.0 + st.epochOffsetMicros)

-- | Adopt a fresh anchor from the rig.
ingestAnchor :: Clock -> Anchor -> Effect Unit
ingestAnchor (Clock ref) a = do
  p <- perfNow
  Ref.modify_ (\s -> s { anchor = Just a, anchorPerf = p, anchorCount = s.anchorCount + 1 }) ref

-- | Override the free-run baseline. Several clocks given the same baseline
-- | share one free-run timeline (and downbeat) with no rig — the laptop-only
-- | analogue of all of them locking to one Link anchor. Touches only the
-- | free-run branch; a live anchor still wins in `read`, so this is a no-op
-- | while the rig is feeding us.
setFreeBaseline :: Clock -> { startMicros :: Number, tempo :: Number } -> Effect Unit
setFreeBaseline (Clock ref) b =
  Ref.modify_ (_ { freeStartMicros = b.startMicros, freeTempo = b.tempo }) ref

-- | Parse an Atlantis Sync Protocol anchor frame:
-- | `anchor <unixMicros> <beat> <tempo> <quantum>`.
parseAnchorLine :: String -> Maybe Anchor
parseAnchorLine line =
  case String.split (Pattern " ") (String.trim line) of
    [ tag, u, b, t, q ] | tag == "anchor" -> ado
      unixMicros <- Number.fromString u
      beat <- Number.fromString b
      tempo <- Number.fromString t
      quantum <- Number.fromString q
      in Anchor { unixMicros, beat, tempo, quantum }
    _ -> Nothing

-- | Read the clock now.
read :: Clock -> Effect ClockReading
read (Clock ref) = do
  st <- Ref.read ref
  p <- perfNow
  let nowMicros = p * 1000.0 + st.epochOffsetMicros
  let reading beat tempo quantum locked =
        let bar = floor (beat / quantum)
        in { beat, bar, phase: beat - toNumber bar * quantum, tempo, quantum, locked
           , anchorCount: st.anchorCount }
  pure case st.anchor of
    Just (Anchor a) | (p - st.anchorPerf) < staleMs ->
      reading (a.beat + (nowMicros - a.unixMicros) * a.tempo / 60000000.0)
              a.tempo a.quantum true
    _ ->
      reading ((nowMicros - st.freeStartMicros) * st.freeTempo / 60000000.0)
              st.freeTempo st.freeQuantum false

-- | Invert the clock: at what wall-clock microsecond will `targetBeat`
-- | occur? Used by the scheduler to place each step slightly ahead.
beatToUnixMicros :: Clock -> Number -> Effect Number
beatToUnixMicros (Clock ref) targetBeat = do
  st <- Ref.read ref
  p <- perfNow
  pure case st.anchor of
    Just (Anchor a) | (p - st.anchorPerf) < staleMs ->
      a.unixMicros + (targetBeat - a.beat) * 60000000.0 / a.tempo
    _ ->
      st.freeStartMicros + targetBeat * 60000000.0 / st.freeTempo

-- | Convert an absolute unix-micros instant into the browser's `performance.now`
-- | millisecond timebase (the timestamp Web MIDI's `send` expects). Scheduling at
-- | an ABSOLUTE time — rather than `performance.now() + delay` computed afresh at
-- | send — stops pipeline latency between computing the fire time and actually
-- | sending from being added on top (the ~130 ms co-sim offset). Uses the same
-- | epoch mapping as `unixMicrosNow` (`unixMicros = perfMs*1000 + epochOffset`).
perfMsAt :: Clock -> Number -> Effect Number
perfMsAt (Clock ref) unixMicros = do
  st <- Ref.read ref
  pure ((unixMicros - st.epochOffsetMicros) / 1000.0)
