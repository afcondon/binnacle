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
  , onAppMessage
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
  -- App-level handler for non-anchor frames (rig replies). Defaults to a no-op;
  -- an app registers one via `onAppMessage`. Anchor lines never reach it — they
  -- are consumed by the clock — so the app only sees protocol replies.
  , appMsg :: Ref.Ref (String -> Effect Unit)
  }

clock :: Binnacle -> Clock
clock (Binnacle b) = b.clock

socket :: Binnacle -> Socket
socket (Binnacle b) = b.socket

-- | Register (or replace) the handler for non-anchor rig frames — e.g. a
-- | `selene-reply …` from a config push. The app filters by prefix.
onAppMessage :: Binnacle -> (String -> Effect Unit) -> Effect Unit
onAppMessage (Binnacle b) cb = Ref.write cb b.appMsg

connect :: Config -> Effect Binnacle
connect cfg = do
  clk <- Clock.newClock { tempo: cfg.tempo }
  sockRef <- Ref.new Nothing
  appRef <- Ref.new (\_ -> pure unit)
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
            Nothing -> do
              cb <- Ref.read appRef
              cb msg
      , onClose: pure unit
      }
  sock <- Transport.open cfg.url handlers
  Ref.write (Just sock) sockRef
  pure (Binnacle { socket: sock, clock: clk, appMsg: appRef })
