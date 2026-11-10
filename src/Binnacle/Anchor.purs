-- | The Link anchor: the one message that tells every program on the rig
-- | where the beat is.
-- |
-- | This module is the REFERENCE for `/link/anchor`. The declaration it
-- | implements is `conformance/LINK-ANCHOR.md`; the vectors every other
-- | implementation replays (Rust, Erlang, C++) are generated from here by
-- | `make vectors`. If this module and the declaration disagree, that is a
-- | bug in one of them, and the vectors are wrong until it is settled.
-- |
-- | Everything here is pure. Receiving, timing and staleness bookkeeping
-- | belong to the caller (`Binnacle.Clock` in the browser).
module Binnacle.Anchor
  ( Anchor(..)
  , Refusal(..)
  , Verdict(..)
  , tempoMinimum
  , tempoMaximum
  , quantumMinimum
  , quantumMaximum
  , unixMicrosMaximum
  , freshForMicros
  , publishPeriodMicros
  , validate
  , beatAt
  , unixMicrosAt
  , isFresh
  , oscHeader
  , oscPacketLength
  , encodeOsc
  , encodeOscUnchecked
  , decodeOsc
  , int64Bytes
  , float64Bytes
  , renderLine
  , parseLine
  , verdictOf
  , verdictName
  , refusalName
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (foldl)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.Number.Format as Format
import Data.String (Pattern(..))
import Data.String as String
import Data.String.Regex (Regex)
import Data.String.Regex as Regex
import Data.String.Regex.Flags (noFlags)
import Data.String.Regex.Unsafe (unsafeRegex)

-- | The affine map from wall clock to Link's beat grid.
-- |
-- | * `unixMicros` — the moment the map was sampled, in microseconds since
-- |   the Unix epoch. An integer on the wire; held as a `Number` here, which
-- |   is exact below 2^53.
-- | * `beat` — Link's beat at that moment. May be negative.
-- | * `tempo` — beats per minute.
-- | * `quantum` — beats per bar.
newtype Anchor = Anchor
  { unixMicros :: Number
  , beat :: Number
  , tempo :: Number
  , quantum :: Number
  }

derive newtype instance Eq Anchor
derive newtype instance Show Anchor

-- | Why something that arrived is not an anchor we will use.
data Refusal
  -- | A different message altogether: another OSC address, another text
  -- | frame, or bytes that are not OSC. Not an error. Dispatch it elsewhere
  -- | or ignore it, and do not count it against the clock.
  = NotAnAnchor
  -- | The address is ours but the type tags are not exactly `,hddd`.
  | WrongTypeTags
  -- | The address and tags are ours but the packet is not exactly 56 bytes.
  | WrongLength
  -- | A text frame that begins `anchor` but does not have four well-formed
  -- | numbers after it.
  | MalformedLine
  -- | `beat`, `tempo` or `quantum` is NaN or infinite.
  | NonFiniteValue
  -- | `unixMicros` is negative or at least 2^53.
  | UnixMicrosOutOfRange
  -- | `tempo` is outside Link's own range.
  | TempoOutOfRange
  -- | `quantum` is outside 1 to 64.
  | QuantumOutOfRange

derive instance Eq Refusal

-- | What a receiver does with an arrival. This three-way split is what the
-- | vectors pin; the finer `Refusal` is advice for a log line.
data Verdict
  = Accept
  -- | It was meant to be an anchor and is not usable. Count it.
  | Refuse
  -- | It was never an anchor. Do not count it.
  | Other

derive instance Eq Verdict

tempoMinimum :: Number
tempoMinimum = 20.0

tempoMaximum :: Number
tempoMaximum = 999.0

quantumMinimum :: Number
quantumMinimum = 1.0

quantumMaximum :: Number
quantumMaximum = 64.0

-- | 2^53. `unixMicros` must be below it, so every implementation can hold it
-- | exactly in a double.
unixMicrosMaximum :: Number
unixMicrosMaximum = 9007199254740992.0

-- | An anchor is fresh until this long after it was RECEIVED, inclusive.
-- | Past that the source is treated as gone.
freshForMicros :: Number
freshForMicros = 2000000.0

-- | How often the producer publishes: 10 Hz.
publishPeriodMicros :: Number
publishPeriodMicros = 100000.0

-- | The whole validity rule. Finiteness is checked before range because a
-- | NaN compares as neither inside nor outside a range, and PureScript's
-- | `>` on a NaN is `true`.
validate :: Anchor -> Either Refusal Anchor
validate anchor@(Anchor a)
  | not (Number.isFinite a.unixMicros) = Left UnixMicrosOutOfRange
  | a.unixMicros < 0.0 || a.unixMicros >= unixMicrosMaximum = Left UnixMicrosOutOfRange
  | Number.floor a.unixMicros /= a.unixMicros = Left UnixMicrosOutOfRange
  | not (Number.isFinite a.beat && Number.isFinite a.tempo && Number.isFinite a.quantum) = Left NonFiniteValue
  | a.tempo < tempoMinimum || a.tempo > tempoMaximum = Left TempoOutOfRange
  | a.quantum < quantumMinimum || a.quantum > quantumMaximum = Left QuantumOutOfRange
  | otherwise = Right anchor

-- | Link's beat at a wall-clock moment. The operations are in this order in
-- | every implementation: subtract, multiply by tempo, divide by sixty
-- | million, add.
beatAt :: Anchor -> Number -> Number
beatAt (Anchor a) unixMicros =
  a.beat + (unixMicros - a.unixMicros) * a.tempo / 60000000.0

-- | The inverse: the wall-clock moment at which a beat falls.
unixMicrosAt :: Anchor -> Number -> Number
unixMicrosAt (Anchor a) beat =
  a.unixMicros + (beat - a.beat) * 60000000.0 / a.tempo

-- | Whether an anchor received `ageMicros` ago still drives the clock.
isFresh :: Number -> Boolean
isFresh ageMicros = ageMicros <= freshForMicros

-- ── OSC ────────────────────────────────────────────────────────────────────

-- | `/link/anchor` and `,hddd`, each NUL-terminated and padded to four bytes.
oscHeader :: Array Int
oscHeader =
  -- /   l    i    n    k    /   a   n    c   h    o    r   NUL padding
  [ 47, 108, 105, 110, 107, 47, 97, 110, 99, 104, 111, 114, 0, 0, 0, 0
  -- ,   h    d    d    d   NUL padding
  , 44, 104, 100, 100, 100, 0, 0, 0
  ]

oscAddressLength :: Int
oscAddressLength = 16

-- | Header (24) plus an int64 and three float64s (32).
oscPacketLength :: Int
oscPacketLength = 56

-- | The packet for a valid anchor. A producer sends nothing else.
encodeOsc :: Anchor -> Either Refusal (Array Int)
encodeOsc = validate >>> map encodeOscUnchecked

-- | The packet for any four numbers, valid or not. For building test
-- | vectors; a producer uses `encodeOsc`.
encodeOscUnchecked :: Anchor -> Array Int
encodeOscUnchecked (Anchor a) =
  oscHeader
    <> int64Bytes a.unixMicros
    <> float64Bytes a.beat
    <> float64Bytes a.tempo
    <> float64Bytes a.quantum

-- | Read one UDP datagram.
decodeOsc :: Array Int -> Either Refusal Anchor
decodeOsc bytes
  | Array.take oscAddressLength bytes /= Array.take oscAddressLength oscHeader = Left NotAnAnchor
  | Array.take (Array.length oscHeader) bytes /= oscHeader = Left WrongTypeTags
  | Array.length bytes /= oscPacketLength = Left WrongLength
  | otherwise = do
      let field index = Array.slice (24 + 8 * index) (32 + 8 * index) bytes
      unixMicros <- int64FromBytes (field 0)
      validate $ Anchor
        { unixMicros
        , beat: float64FromBytes (field 1)
        , tempo: float64FromBytes (field 2)
        , quantum: float64FromBytes (field 3)
        }

-- | Eight big-endian bytes of a non-negative integer below 2^53.
int64Bytes :: Number -> Array Int
int64Bytes value = Array.reverse (go 8 value)
  where
  go :: Int -> Number -> Array Int
  go remaining rest
    | remaining == 0 = []
    | otherwise =
        let
          quotient = Number.floor (rest / 256.0)
          byte = rest - quotient * 256.0
        in
          Array.cons (numberToByte byte) (go (remaining - 1) quotient)

-- | A big-endian signed int64, refused unless it is in 0 ..< 2^53. The top
-- | eleven bits must be clear, which also rules out every negative value.
int64FromBytes :: Array Int -> Either Refusal Number
int64FromBytes bytes =
  case Array.take 2 bytes of
    [ first, second ] | first == 0 && second < 32 ->
      Right (foldl (\total byte -> total * 256.0 + toNumber byte) 0.0 bytes)
    _ -> Left UnixMicrosOutOfRange

foreign import float64Bytes :: Number -> Array Int

foreign import float64FromBytes :: Array Int -> Number

foreign import numberToByte :: Number -> Int

-- ── The text frame ─────────────────────────────────────────────────────────

-- | `anchor <unixMicros> <beat> <tempo> <quantum>`: the same four values as
-- | decimal text, single spaces between. This is how Architeuthis forwards
-- | the anchor to browsers.
renderLine :: Anchor -> String
renderLine (Anchor a) =
  String.joinWith " "
    [ "anchor"
    , Format.toString a.unixMicros
    , Format.toString a.beat
    , Format.toString a.tempo
    , Format.toString a.quantum
    ]

-- | Read one text frame. Surrounding whitespace is ignored; anything whose
-- | first word is not `anchor` is somebody else's frame.
parseLine :: String -> Either Refusal Anchor
parseLine line =
  case String.split (Pattern " ") (String.trim line) of
    [ "anchor", unixMicros, beat, tempo, quantum ] ->
      case
        ado
          parsedMicros <- decimal wholeNumber unixMicros
          parsedBeat <- decimal realNumber beat
          parsedTempo <- decimal realNumber tempo
          parsedQuantum <- decimal realNumber quantum
          in
            Anchor
              { unixMicros: parsedMicros
              , beat: parsedBeat
              , tempo: parsedTempo
              , quantum: parsedQuantum
              }
        of
        Nothing -> Left MalformedLine
        Just anchor -> validate anchor
    words
      | Array.head words == Just "anchor" -> Left MalformedLine
      | otherwise -> Left NotAnAnchor

decimal :: Regex -> String -> Maybe Number
decimal shape text
  | Regex.test shape text = Number.fromString text
  | otherwise = Nothing

-- | Digits only: `unixMicros` is an integer and is written as one.
wholeNumber :: Regex
wholeNumber = unsafeRegex "^[0-9]+$" noFlags

-- | A plain decimal, with an optional sign, fraction and exponent.
realNumber :: Regex
realNumber = unsafeRegex "^-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$" noFlags

-- ── Verdicts ───────────────────────────────────────────────────────────────

verdictOf :: forall a. Either Refusal a -> Verdict
verdictOf = case _ of
  Right _ -> Accept
  Left NotAnAnchor -> Other
  Left _ -> Refuse

verdictName :: Verdict -> String
verdictName = case _ of
  Accept -> "accept"
  Refuse -> "refuse"
  Other -> "other"

refusalName :: Refusal -> String
refusalName = case _ of
  NotAnAnchor -> "not-an-anchor"
  WrongTypeTags -> "wrong-type-tags"
  WrongLength -> "wrong-length"
  MalformedLine -> "malformed-line"
  NonFiniteValue -> "non-finite-value"
  UnixMicrosOutOfRange -> "unix-micros-out-of-range"
  TempoOutOfRange -> "tempo-out-of-range"
  QuantumOutOfRange -> "quantum-out-of-range"
