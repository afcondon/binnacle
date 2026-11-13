-- | `/link/peers` and `/clock/origin` as Hawser descriptions: each message
-- | said once, as a name and its fields. `Reference.LinkPeers` and
-- | `Reference.ClockOrigin` are these, given the names the cases use.
module Reference.Described
  ( peers
  , origin
  ) where

import Prelude

import Hawser.Message (Message, field, message)
import Hawser.Value (finite, notNegative, number, whole)

peers :: Message { peers :: Int }
peers = message "/link/peers" "How many other Link peers share the session." $
  { peers: _ } <$> field "peers" _.peers (notNegative 0 "negative-count" whole) "the count of other peers"

origin :: Message { beat :: Number }
origin = message "/clock/origin" "The beat that clock divisions count from." $
  { beat: _ } <$> field "beat" _.beat (finite number) "the beat of the last Start, on Link's grid"
