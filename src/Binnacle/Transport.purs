-- | A minimal WebSocket transport for the Atlantis Sync Protocol: text
-- | frames in and out. Deliberately thin — the protocol is line-oriented
-- | text, so there's no codec layer here.
module Binnacle.Transport
  ( Socket
  , Handlers
  , open
  , send
  , isConnected
  ) where

import Prelude

import Effect (Effect)
import Effect.Uncurried (EffectFn1, EffectFn2, mkEffectFn1, runEffectFn1, runEffectFn2)

foreign import data Socket :: Type

-- | App-facing callbacks. `onMessage` receives raw text frames.
type Handlers =
  { onOpen :: Effect Unit
  , onMessage :: String -> Effect Unit
  , onClose :: Effect Unit
  }

type FFIHandlers =
  { onOpen :: Effect Unit
  , onMessage :: EffectFn1 String Unit
  , onClose :: Effect Unit
  }

foreign import openImpl :: EffectFn2 String FFIHandlers Socket
foreign import sendImpl :: EffectFn2 Socket String Unit
foreign import isConnectedImpl :: EffectFn1 Socket Boolean

-- | Open a WebSocket to the rig and wire up the handlers.
open :: String -> Handlers -> Effect Socket
open url h = runEffectFn2 openImpl url
  { onOpen: h.onOpen
  , onMessage: mkEffectFn1 h.onMessage
  , onClose: h.onClose
  }

-- | Send one text frame. No-op when there is no live connection — a dropped
-- | frame beats an exception inside a Halogen handler. The socket re-dials
-- | itself (see Transport.js), so a gap is seconds rather than permanent.
send :: Socket -> String -> Effect Unit
send = runEffectFn2 sendImpl

-- | Is a live connection up right now? For surfaces that would rather show
-- | "not talking to the rig" than let the user infer it from nothing happening.
isConnected :: Socket -> Effect Boolean
isConnected = runEffectFn1 isConnectedImpl
