# `/clock/origin` — the declaration

The beat that clock divisions count from. A clocked device counts its
divisions from its last Start, so the beat of that Start is where a ÷3 or a
÷8 falls. Diaphus sends that beat to es9-daemon, which counts its own clocks
and Euclids from it, so the divisions of the two coincide.

`test/Reference/ClockOrigin.purs` is the reference implementation.
`conformance/vectors/clock-origin.json` is the set of cases every
implementation replays. Declared 2026-11-13, in the manner of
`LINK-ANCHOR.md`, which this file follows wherever it says nothing.

## The value

One number: a beat on Link's grid, the same grid as the anchor's `beat`. It
may be negative and need not be whole. It is 0 until a device has been
started.

## Validity

The beat is finite: not NaN, not infinite. A NaN origin would make every
derived beat NaN, and a free-running clock keeps the phase it last had, so
the damage would outlive the message.

## When it is sent

Ten times a second, beside the anchor.

## The packet

One bare OSC message per datagram. Exactly 28 bytes:

| Bytes | Content |
|---|---|
| 0–15 | `/clock/origin`, a NUL, two NULs of padding |
| 16–19 | `,d`, two NULs |
| 20–27 | `beat`, big-endian IEEE 754 binary64 |

## The verdict

1. If the first 16 bytes are not the address above, the verdict is `other`.
2. Otherwise, if bytes 16–19 are not exactly the type tags above, or the
   datagram is not exactly 28 bytes, the verdict is `refuse`.
3. Otherwise, if the beat is not finite, the verdict is `refuse`.
4. Otherwise `accept`.

A refusal is counted, in the same count as refused anchors, and the held
origin is kept.

## Who holds a copy

| Program | Language | Role | Port | Held by |
|---|---|---|---|---|
| Diaphus | Rust | producer | sends to 57123 | the `link-anchor` crate |
| es9-daemon | Rust | receiver | 57123 | the `link-anchor` crate |

Both ends are Rust and share one implementation, which replays the vectors
in its own `cargo test`.

## Conforming

Replay `osc` in the vector file: decode `hex`; the verdict must equal
`expect`; when accepted, the beat must equal `beat` exactly. A producer is
held to the accepted cases: encoding `beat` must give `hex` byte for byte.

The file carries `"clock-origin-vectors": 1`. A replayer asserts the number
it understands. Not finding the file is a failure, not a skip.

## Changing this

Change this document, then `test/Test/Companions.purs`, whose verdicts are
written by hand, then the reference until `make test` passes, then
`make vectors`.
