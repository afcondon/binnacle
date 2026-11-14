# What Diaphus reads — the declaration

Diaphus listens for OSC on UDP `127.0.0.1:57122`. Through it the rest of the
rig sends timed MIDI, and moves the Link session's tempo and transport.

`wires/src/Wires/Daemons.purs` is the reference: each message described once.
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

## What Diaphus holds

Since 2026-11-14 Diaphus reads exactly what this file declares
(`read_packet` in `src/main.rs`):

- one bare message per datagram: a bundle is not one of these messages and
  is ignored;
- the type tags must be exactly the declared ones, and the arguments must
  end exactly where the datagram does;
- every value must be inside its declared range: a channel of 17, a note
  of 128 or a tempo of 19 is **refused**, not truncated or clamped.

A refused datagram is not acted on. It is counted, and the first of each
kind (address and rule) is said on Diaphus's stderr.

So the vectors come in four parts:

| Part | Meaning | Held on |
|---|---|---|
| `packets` | What a writer produces: the values, and the exact bytes | Writers, byte for byte. Diaphus must read these values |
| `refused` | Addressed to Diaphus and not as declared | Diaphus must refuse it, for the stated reason |
| `other` | Never one of these messages | Diaphus must ignore it |
| `tolerated` | Not as declared, but sent on the rig | Empty. Diaphus would have to go on reading it |

### Tolerated: nothing

Until 2026-11-14 Architeuthis sent `/link/set-tempo` as a binary32 and
Diaphus read it. Architeuthis now sends through the description
(`rig_wire.erl`), and that packet is in `refused`. The part stays in the
file so that the next such case has a place; a reader checks it is empty.

## Who writes, and who reads

Diaphus, the one reader, replays all four parts in `cargo test`
(`inbound_tests`).

| Program | Language | Sends | Held by |
|---|---|---|---|
| Architeuthis (`rig_wire.erl`, for `Tidal/MIDIBridge.erl`) | Erlang, encoding with the description itself | the four `/midi/…/at`, `/link/set-tempo` | `make test-erl` (`rig_wire_tests`) |
| DeepStar (`internal/rig/midi.go`) | Go | `/midi/note/at`, `/midi/cc/at` | `go test ./internal/rig` (`wire_test.go`) |
| Itajara (`daemon/src/link.rs`) | Rust | `/link/set-tempo`, `/link/play` | `cargo test` (`link::writer_tests`) |
| fh2-config (`FH2/ClockOrigin.js`) | JavaScript | `/clock/restart` | `node conformance/wire.mjs` |
| Reef's conformance emitter, Diaphus's probe | JavaScript, Python | `/midi/note/at` | not yet |

## Conforming

A **reader** replays `packets`: each `hex` must be read as the message at
`address` with the arguments in `values`, in order. It replays `refused`
(the verdict is refuse, and `reason` is the tag of the rule broken; a case
with an empty `reason` was made mechanically and any refusal will do) and
`other`, and checks that `tolerated` is empty.

A **writer** replays `packets`: encoding `values` for `address` must give
`hex` byte for byte.

The file carries `"diaphus-inbound-vectors": 1`. A replayer asserts the
number it understands. Not finding the file is a failure, not a skip.

## Changing this

Change this document, then `test/Test/Daemons.purs`, whose cases are written
by hand, then the descriptions until `make test` passes, then `make vectors`.
