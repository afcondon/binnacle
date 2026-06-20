-- | Binnacle — the deck housing that holds an Atlantis-synced app's
-- | navigation instruments. `connect` opens the rig transport, builds the
-- | clock, subscribes to the Link anchor on open, and feeds incoming
-- | anchors into the clock. From the returned handle an app gets its
-- | `clock` (read beat/bar/phase) and `socket` (drive output + scheduler).
-- |
-- | Typical use:
-- | ```
-- | bin <- Binnacle.connect { url: "ws://127.0.0.1:3012/ws", tempo: 120.0 }
-- | cancel <- Scheduler.startGrid (Binnacle.clock bin) gridCfg \tick -> do
-- |   -- advance your model, then for each event:
-- |   Output.cvOut  (Binnacle.socket bin) { bus, value: voct tuning note }
-- |   Output.fireAt (Binnacle.socket bin) { bus: gate, value: 0.5
-- |                                        , durMs: 40.0, delayMs: tick.delayMs }
-- | ```
module Binnacle
  ( Binnacle
  , Config
  , connect
  , clock
  , socket
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Ref as Ref
import Binnacle.Clock (Clock)
import Binnacle.Clock as Clock
import Binnacle.Output (clockSubscribe)
import Binnacle.Transport (Socket)
import Binnacle.Transport as Transport

type Config =
  { url :: String     -- rig WebSocket, e.g. "ws://127.0.0.1:3012/ws"
  , tempo :: Number   -- free-run fallback tempo until an anchor arrives
  }

newtype Binnacle = Binnacle
  { socket :: Socket
  , clock :: Clock
  }

clock :: Binnacle -> Clock
clock (Binnacle b) = b.clock

socket :: Binnacle -> Socket
socket (Binnacle b) = b.socket

connect :: Config -> Effect Binnacle
connect cfg = do
  clk <- Clock.newClock { tempo: cfg.tempo }
  sockRef <- Ref.new Nothing
  let
    handlers =
      { onOpen: do
          msock <- Ref.read sockRef
          case msock of
            Just s -> clockSubscribe s
            Nothing -> pure unit
      , onMessage: \msg ->
          case Clock.parseAnchorLine msg of
            Just a -> Clock.ingestAnchor clk a
            Nothing -> pure unit
      , onClose: pure unit
      }
  sock <- Transport.open cfg.url handlers
  Ref.write (Just sock) sockRef
  pure (Binnacle { socket: sock, clock: clk })
