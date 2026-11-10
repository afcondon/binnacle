-- | Holds the reference to the declared cases. Every failure is listed, then
-- | the run throws, so `spago test` exits non-zero.
module Test.Main (main) where

import Prelude

import Binnacle.Anchor (Anchor, Refusal, Verdict, beatAt, decodeOsc, encodeOsc, isFresh, parseLine, refusalName, renderLine, verdictName, verdictOf)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.Number (abs)
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import Test.Hex (hex)
import Test.Vectors (BeatCase, FreshCase, OscCase, TextCase, beatCases, beatTolerance, canonical, canonicalHex, freshCases, oscCases, textCases)

main :: Effect Unit
main = do
  let
    failures =
      canonicalFailures
        <> Array.concatMap oscFailures oscCases
        <> Array.concatMap textFailures textCases
        <> Array.concatMap beatFailures beatCases
        <> Array.concatMap freshFailures freshCases
        <> duplicateNames "osc" (map _.name oscCases)
        <> duplicateNames "text" (map _.name textCases)
        <> duplicateNames "beatAt" (map _.name beatCases)
  for_ failures \failure -> log ("FAIL  " <> failure)
  log
    ( show (Array.length oscCases) <> " osc, "
        <> show (Array.length textCases)
        <> " text, "
        <> show (Array.length beatCases)
        <> " beatAt, "
        <> show (Array.length freshCases)
        <> " fresh cases; "
        <> show (Array.length failures)
        <> " failures"
    )
  unless (Array.null failures) (throw "the reference disagrees with its declared cases")

-- | The encoder against a packet built outside this codebase.
canonicalFailures :: Array String
canonicalFailures =
  case encodeOsc canonical of
    Right bytes | hex bytes == canonicalHex -> []
    Right bytes -> [ "canonical packet is " <> hex bytes <> ", expected " <> canonicalHex ]
    Left refusal -> [ "canonical anchor refused by the encoder: " <> refusalName refusal ]

oscFailures :: OscCase -> Array String
oscFailures testCase =
  let
    decoded = decodeOsc testCase.bytes
  in
    verdictFailures ("osc/" <> testCase.name) testCase.expect testCase.anchor decoded
      <> case testCase.anchor of
        Just anchor | encodeOsc anchor /= Right testCase.bytes ->
          [ "osc/" <> testCase.name <> ": encoding the expected anchor does not give the packet back" ]
        _ -> []

textFailures :: TextCase -> Array String
textFailures testCase =
  let
    parsed = parseLine testCase.line
  in
    verdictFailures ("text/" <> testCase.name) testCase.expect testCase.anchor parsed
      <> case testCase.anchor of
        Just anchor | parseLine (renderLine anchor) /= Right anchor ->
          [ "text/" <> testCase.name <> ": rendering the expected anchor and parsing it does not give it back" ]
        _ -> []

verdictFailures :: String -> Verdict -> Maybe Anchor -> Either Refusal Anchor -> Array String
verdictFailures label expect expectedAnchor actual =
  let
    verdict = verdictOf actual
  in
    if verdict /= expect then
      [ label <> ": declared " <> verdictName expect <> ", reference says " <> describe actual ]
    else case expectedAnchor, actual of
      Just anchor, Right got | got /= anchor ->
        [ label <> ": accepted as " <> show got <> ", declared " <> show anchor ]
      Nothing, Right _ ->
        [ label <> ": declared to be accepted but no anchor is declared" ]
      _, _ -> []

describe :: Either Refusal Anchor -> String
describe = case _ of
  Right anchor -> "accept " <> show anchor
  Left refusal -> verdictName (verdictOf (Left refusal :: Either Refusal Anchor)) <> " (" <> refusalName refusal <> ")"

beatFailures :: BeatCase -> Array String
beatFailures testCase =
  let
    got = beatAt testCase.anchor testCase.atUnixMicros
  in
    if abs (got - testCase.beat) <= beatTolerance then []
    else [ "beatAt/" <> testCase.name <> ": got " <> show got <> ", declared " <> show testCase.beat ]

freshFailures :: FreshCase -> Array String
freshFailures testCase =
  if isFresh testCase.ageMicros == testCase.fresh then []
  else [ "fresh/" <> show testCase.ageMicros <> ": declared " <> show testCase.fresh ]

duplicateNames :: String -> Array String -> Array String
duplicateNames section names =
  if Array.length (Array.nub names) == Array.length names then []
  else [ section <> ": two cases share a name" ]
