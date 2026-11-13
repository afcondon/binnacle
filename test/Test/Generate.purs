-- | Writes the vector file to standard output. `make vectors` redirects it to
-- | `conformance/vectors/link-anchor.json`.
-- |
-- | Each case carries the DECLARED verdict from `Test.Vectors`. The `reason`
-- | beside a refusal is the reference's own finer classification, and is
-- | advice only: an implementation is held to the verdict, not the reason.
module Test.Generate (main, peers, origin) where

import Prelude

import Binnacle.Anchor (Anchor(..), Refusal, Verdict(..), decodeOsc, freshForMicros, oscPacketLength, parseLine, publishPeriodMicros, quantumMaximum, quantumMinimum, refusalName, tempoMaximum, tempoMinimum, unixMicrosMaximum, verdictName)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Foreign (Foreign)
import Simple.JSON (write)
import Test.Companions (originVectors, peersVectors)
import Test.Hex (hex)
import Test.Vectors (beatCases, beatTolerance, freshCases, oscCases, textCases)

foreign import pretty :: Foreign -> String

type Fields =
  { unixMicros :: Number
  , beat :: Number
  , tempo :: Number
  , quantum :: Number
  }

fields :: Anchor -> Fields
fields (Anchor anchor) = anchor

-- | The reference's reason, for a case declared to be refused.
reason :: forall a. Verdict -> Either Refusal a -> Maybe String
reason expect actual = case expect, actual of
  Refuse, Left refusal -> Just (refusalName refusal)
  _, _ -> Nothing

main :: Effect Unit
main = log $ pretty $ write
  { "link-anchor-vectors": 1
  , declaration: "conformance/LINK-ANCHOR.md"
  , generatedBy: "Test.Generate in binnacle; do not edit by hand, run `make vectors`"
  , constants:
      { tempoMinimum
      , tempoMaximum
      , quantumMinimum
      , quantumMaximum
      , unixMicrosMaximum
      , freshForMicros
      , publishPeriodMicros
      , oscPacketLength
      , beatTolerance
      }
  , osc: oscCases <#> \testCase ->
      { name: testCase.name
      , why: testCase.why
      , hex: hex testCase.bytes
      , expect: verdictName testCase.expect
      , anchor: map fields testCase.anchor
      , reason: reason testCase.expect (decodeOsc testCase.bytes)
      }
  , text: textCases <#> \testCase ->
      { name: testCase.name
      , why: testCase.why
      , line: testCase.line
      , expect: verdictName testCase.expect
      , anchor: map fields testCase.anchor
      , reason: reason testCase.expect (parseLine testCase.line)
      }
  , beatAt: beatCases <#> \testCase ->
      { name: testCase.name
      , anchor: fields testCase.anchor
      , atUnixMicros: testCase.atUnixMicros
      , beat: testCase.beat
      }
  , fresh: freshCases
  }

-- | `conformance/vectors/link-peers.json`.
peers :: Effect Unit
peers = log (pretty peersVectors)

-- | `conformance/vectors/clock-origin.json`.
origin :: Effect Unit
origin = log (pretty originVectors)
