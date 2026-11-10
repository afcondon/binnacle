# `/link/anchor` — the declaration

The one message that tells every program on the rig where the beat is.
Diaphus samples Ableton Link and publishes this about ten times a second;
everything else that needs the bar reads it.

This file says what the message is. `src/Binnacle/Anchor.purs` is the
reference implementation of it. `conformance/vectors/link-anchor.json` is
the set of cases every other implementation replays. If the three disagree,
that is a bug, and it is settled here first.

Decided 2026-11-10, after finding seven hand-written copies with four
different validity rules.

## The value

An anchor is four numbers: an affine map from wall clock to Link's beat grid.

| Field | Meaning | Unit | On the wire |
|---|---|---|---|
| `unixMicros` | when the map was sampled | microseconds since the Unix epoch | signed 64-bit integer |
| `beat` | Link's beat at that moment | beats; may be negative | 64-bit float |
| `tempo` | how fast the beat advances | beats per minute | 64-bit float |
| `quantum` | length of a bar | beats | 64-bit float |

## Validity

An anchor is valid when all of these hold. A receiver uses a valid anchor
and nothing else.

1. `0 <= unixMicros < 2^53`. The upper bound lets every implementation hold
   the time exactly in a double.
2. `beat`, `tempo` and `quantum` are finite: not NaN, not infinite.
3. `20 <= tempo <= 999`. This is Link's own range.
4. `1 <= quantum <= 64`. It need not be a whole number.

Check finiteness before range. A NaN is neither inside nor outside a range,
and in several languages a range test on a NaN gives the wrong answer.

There is one producer, so a receiver gains nothing by being lenient. An
anchor that fails any rule means the message has changed shape or the
producer is broken, and either should be visible.

## What a receiver does with an arrival

Every arrival gets one of three verdicts.

| Verdict | Meaning | What to do |
|---|---|---|
| `accept` | a valid anchor | replace the held anchor; note when it arrived |
| `refuse` | meant to be an anchor, and not usable | keep the held anchor; **count it** |
| `other` | never an anchor | dispatch it elsewhere or ignore it; do not count it |

The refusal count must be readable from outside the process (a status verb,
a snapshot field, a log line on change). A listener that is hearing bad
anchors and one that is hearing nothing must not look the same.

## Using an anchor

Link's beat at wall-clock time `t`, in microseconds:

    beat(t) = beat + (t - unixMicros) * tempo / 60000000

Do the operations in that order: subtract, multiply, divide, add. Results
across implementations agree to within `1e-9` beats.

The bar is `floor(beat(t) / quantum)` and the position in the bar is the
remainder.

## Freshness

An anchor is fresh while `age <= 2,000,000` microseconds, where `age` is
measured from when it was **received**, on the receiver's own clock. Past
that the source is treated as gone, and a receiver falls back to whatever
it does with no clock. Twenty publications fit in that window, so one lost
packet never trips it.

## Encoding 1: OSC over UDP

One bare OSC message per datagram, never a bundle. Exactly 56 bytes:

| Bytes | Content |
|---|---|
| 0–15 | `/link/anchor`, a NUL, three NULs of padding |
| 16–23 | `,hddd`, a NUL, two NULs of padding |
| 24–31 | `unixMicros`, big-endian signed 64-bit integer |
| 32–39 | `beat`, big-endian IEEE 754 binary64 |
| 40–47 | `tempo`, the same |
| 48–55 | `quantum`, the same |

Deciding the verdict:

1. If the first 16 bytes are not the address above, the verdict is `other`.
   This covers other OSC messages on the same port, bundles, and anything
   too short to hold the address.
2. Otherwise, if bytes 16–23 are not exactly the type tags above, or the
   datagram is not exactly 56 bytes, the verdict is `refuse`.
3. Otherwise decode the four values and apply the validity rule.

The type tags are matched exactly. An `i` for the time or an `f` for a
value is refused, not converted.

Because the layout is fixed, a receiver needs no OSC library to read it:
compare 24 bytes, check the length, read four big-endian numbers.

## Encoding 2: the text frame

Architeuthis forwards the anchor to browsers over its WebSocket as a line
of text:

    anchor <unixMicros> <beat> <tempo> <quantum>

- Leading and trailing whitespace is ignored.
- Words are divided by single spaces and nothing else.
- If the first word is not `anchor`, the verdict is `other`.
- Otherwise there must be exactly four more words, or the verdict is
  `refuse`.
- `unixMicros` is digits only: `[0-9]+`.
- The other three are plain decimals:
  `-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?`. No leading plus, no bare
  fraction, no `NaN`, no `Infinity`, no trailing letters.
- Then the validity rule applies, as for the packet.

A writer may print the values with any number of digits that fits the
grammar. The text frame is therefore a rounding of the anchor, not a copy:
a reader gets what the writer printed. Six decimals of a beat is about a
microsecond at 120 bpm.

## Who holds a copy

| Program | Language | Role | Port | Held by |
|---|---|---|---|---|
| Diaphus | Rust | producer | sends to each port below | the `link-anchor` crate |
| Architeuthis (`tidal_link_anchor.erl`) | Erlang | receiver; writes the text frame | 57121 | `make test-erl` |
| es9-daemon | Rust | receiver | 57123 | the `link-anchor` crate |
| Itajara | Rust | receiver | 57125 | the `link-anchor` crate |
| Continuo (`src/LinkAnchor.h`) | C++ | receiver | 57127 | `ctest`, target `link_anchor_conformance` |
| Binnacle (`Binnacle.Anchor`) | PureScript | reads the text frame; the reference | WebSocket | `make test` |

The three Rust programs share one implementation, `rust/link-anchor` in this
repository, which replays the vectors in its own `cargo test`. The Erlang
and C++ receivers each have their own implementation and their own replay.

All ports are UDP on `127.0.0.1`. How a receiver comes to be on Diaphus's
list is outside this declaration.

## Conforming

An implementation conforms when its own test suite replays
`conformance/vectors/link-anchor.json` and every case passes:

- `osc` — decode `hex`; the verdict must equal `expect`; when accepted, the
  four values must equal `anchor` exactly.
- `text` — the same, for `line`.
- `beatAt` — `beat(atUnixMicros)` for `anchor` must be within
  `constants.beatTolerance` of `beat`.
- `fresh` — an anchor of age `ageMicros` must be fresh or not, as `fresh` says.

A producer is additionally held to the `osc` cases marked `accept`:
encoding `anchor` must give `hex` byte for byte.

`reason` beside a refused case is the reference's finer classification. It
is advice for a log line. Implementations are held to the verdict only.

An implementation that has no text frame skips `text`; one that never
extrapolates skips `beatAt`. It says so in its test, by name.

The file carries `"link-anchor-vectors": 1`. A replayer asserts the number
it understands and fails on any other.

`conformance/replay.py` is a complete replayer in about a hundred lines,
written from this document and sharing no code with the reference. It is
the example to port from, and it runs as part of `make test`.

## Changing this

Change this document, then `test/Test/Vectors.purs`, whose verdicts are
written by hand, then the reference until `make test` passes, then
`make vectors`. `make check-vectors` fails if the committed vector file is
not what the cases generate.
