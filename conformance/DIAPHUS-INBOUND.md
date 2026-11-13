# What Diaphus reads — the declaration

Diaphus listens for OSC on UDP `127.0.0.1:57122`. Through it the rest of the
rig sends timed MIDI, and moves the Link session's tempo and transport.

`test/Reference/Daemons.purs` is the reference: each message described once.
`conformance/vectors/diaphus-inbound.json` is generated from it. If the
three disagree, that is a bug, and it is settled here first.

Declared 2026-11-13, from a survey of every sender on the rig. Before this
the shapes were a comment in `diaphus/src/main.rs` and five hand-written
encoders in five languages.

## The messages

One bare OSC message per datagram, never a bundle. Numbers are big-endian.
A string is UTF-8, a NUL, and NULs to a multiple of four bytes.

<!-- generated:diaphus -->
| Address | Tags | Arguments, in order | Meaning |
|---|---|---|---|
| `/midi/note/at` | `,siiiih` | `port` string; `channel` whole number, 1 to 16; `note` whole number, 0 to 127; `velocity` whole number, 0 to 127; `durationMs` whole number, zero or more; `unixMicros` whole number, below 2^53 in size, zero or more | A note of a given length, at a moment. |
| `/midi/on/at` | `,siiih` | `port` string; `channel` whole number, 1 to 16; `note` whole number, 0 to 127; `velocity` whole number, 0 to 127; `unixMicros` whole number, below 2^53 in size, zero or more | A note-on alone, at a moment. |
| `/midi/off/at` | `,siih` | `port` string; `channel` whole number, 1 to 16; `note` whole number, 0 to 127; `unixMicros` whole number, below 2^53 in size, zero or more | A note-off alone, at a moment. |
| `/midi/cc/at` | `,siiih` | `port` string; `channel` whole number, 1 to 16; `controller` whole number, 0 to 127; `value` whole number, 0 to 127; `unixMicros` whole number, below 2^53 in size, zero or more | A control change, at a moment. |
| `/link/set-tempo` | `,d` | `bpm` number, finite, 20.0 to 999.0 | Set the Link session's tempo, for every peer. |
| `/link/play` | `,i` | `on` whole number, 0 to 1 | Start the session's transport on the next bar line, or stop it now. |
| `/clock/restart` | `,` |  | Start every clocked port again on the next bar line. |
<!-- /generated:diaphus -->

The table is generated from the descriptions by `make vectors`. Do not edit
it here.

A moment is microseconds since the Unix epoch, on the sender's wall clock,
as in `/link/anchor`. Diaphus places the MIDI on the kernel's clock from it.

## What this declares, and what it does not yet hold

This file says what a **writer** must produce. Diaphus reads more loosely:

- it takes a bundle apart and reads each message in it;
- it does not check ranges: a channel of 17 or a note of 128 is truncated,
  not refused;
- `/link/set-tempo` may carry a binary32, and is clamped to 20 to 999, not
  refused outside it;
- `/link/play` may carry a float or a boolean.

So the vectors come in four parts:

| Part | Meaning | Held on |
|---|---|---|
| `packets` | What a writer produces: the values, and the exact bytes | Writers, byte for byte. Diaphus must read these values |
| `tolerated` | Not as declared, but sent on the rig today | Diaphus must go on reading it |
| `refused` | Addressed to Diaphus and not as declared | The reference only, for now |
| `other` | Never one of these messages | The reference; Diaphus logs and ignores |

Tightening Diaphus to refuse what is in `refused` is a later, deliberate
step, taken only when `tolerated` is empty.

### Tolerated today

- **`/link/set-tempo ,f`.** Architeuthis sends the tempo as a binary32
  (`Tidal/MIDIBridge.erl`). Itajara sends the declared binary64. This is
  the one address on this wire that two senders encode differently.

## Who writes, and who reads

Diaphus, the one reader, replays `packets` and `tolerated` in `cargo test`
(`inbound_tests`).

| Program | Language | Sends | Held by |
|---|---|---|---|
| Architeuthis (`Tidal/MIDIBridge.erl`) | Erlang | the four `/midi/…/at`, `/link/set-tempo` | not yet |
| DeepStar (`internal/rig/midi.go`) | Go | `/midi/note/at`, `/midi/cc/at` | `go test ./internal/rig` (`wire_test.go`) |
| Itajara (`daemon/src/link.rs`) | Rust | `/link/set-tempo`, `/link/play` | `cargo test` (`link::writer_tests`) |
| fh2-config (`FH2/ClockOrigin.js`) | JavaScript | `/clock/restart` | `node conformance/wire.mjs` |
| Reef's conformance emitter, Diaphus's probe | JavaScript, Python | `/midi/note/at` | not yet |

## Conforming

A **reader** replays `packets` and `tolerated`: each `hex` must be read as
the message at `address` with the arguments in `values`, in order.

A **writer** replays `packets`: encoding `values` for `address` must give
`hex` byte for byte.

A strict reader also replays `refused` (the verdict is refuse; `reason` is
the reference's tag and is advice) and `other`.

The file carries `"diaphus-inbound-vectors": 1`. A replayer asserts the
number it understands. Not finding the file is a failure, not a skip.

## Changing this

Change this document, then `test/Test/Daemons.purs`, whose cases are written
by hand, then the descriptions until `make test` passes, then `make vectors`.
