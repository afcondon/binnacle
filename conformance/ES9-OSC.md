# What es9-daemon reads over OSC — the declaration

es9-daemon listens for OSC on UDP port 57130. Through it the rest of the rig
sets voltages on the ES-9's sixteen buses and on the ES-5 and ESX-8CV
behind it.

`wires/src/Wires/Daemons.purs` is the reference: each message described once.
`conformance/vectors/es9-osc.json` is generated from it. If the three
disagree, that is a bug, and it is settled here first.

Declared 2026-11-13, from a survey of every sender on the rig. Before this
the shapes were a `match` on strings in `es9-daemon/src/main.rs` and hand
encoders in Erlang (three), Go, JavaScript and Rust.

## The messages

One bare OSC message per datagram, never a bundle. Numbers are big-endian.
Every level and every time is a binary32.

<!-- generated:es9 -->
| Address | Tags | Arguments, in order | Meaning |
|---|---|---|---|
| `/cv` | `,if` | `bus` whole number, 0 to 15; `value` number, finite | Set a bus to a level and hold it. |
| `/cv/slew` | `,iff` | `bus` whole number, 0 to 15; `value` number, finite; `lagSeconds` number, finite, zero or more | Glide a bus to a level. |
| `/cv/trig` | `,iff` | `bus` whole number, 0 to 15; `value` number, finite; `durationMs` number, finite, zero or more | Set a bus to a level now, and back to zero after a time. |
| `/cv/trig/at` | `,ifff` | `bus` whole number, 0 to 15; `value` number, finite; `durationMs` number, finite, zero or more; `delayMs` number, finite, zero or more | As `/cv/trig`, starting a given time after arrival, to the sample. |
| `/esx` | `,if` | `slot` whole number, 0 to 7; `value` number, finite | Set one ESX-8CV output. Turns the ES-5 encoding on. |
| `/esx5gate` | `,ii` | `bit` whole number, 0 to 7; `state` whole number, 0 to 1 | Set one of the ES-5's own gates. Turns the ES-5 encoding on. |
| `/esx/enable` | `,i` | `on` whole number, 0 to 1 | Turn the ES-5 encoding on or off. Nothing on the rig sends this. |
| `/tidal/gate/trig` | `,if` | `channel` whole number, 0 to 7; `durationMs` number, finite, zero or more | Raise a gate bus by its index for a time. |
| `/tidal/gate` | `,ii` | `channel` whole number, 0 to 7; `state` whole number, 0 to 1 | Set a gate bus (8 to 15) by its index. Nothing on the rig sends this. |
| `/tidal/cv` | `,if` | `channel` whole number, 0 to 3; `value` number, finite | Set a CV bus (12 to 15) by its index, at half scale. Nothing on the rig sends this. |
| `/tidal/cv/slew` | `,iff` | `channel` whole number, 0 to 3; `value` number, finite; `lagSeconds` number, finite, zero or more | Glide a CV bus by its index, at half scale. Nothing on the rig sends this. |
<!-- /generated:es9 -->

The table is generated from the descriptions by `make vectors`. Do not edit
it here.

A level of 1.0 is full scale, which is 10 V on an ES-9 bus. The daemon
clamps a level to ±1.

## What es9-daemon holds

Since 2026-11-14 es9-daemon reads exactly what this file declares
(`read_packet` in `src/main.rs`), by the rule Diaphus follows
(`DIAPHUS-INBOUND.md`): one bare message per datagram, the exact type
tags, a length that ends with the last argument, every value in range. A
refused datagram is not acted on; it is counted, the count is the
`osc-refusals` of the `link` verb, and the first of each kind is said on
stderr.

The vectors come in four parts, as for Diaphus: `packets`, `refused`,
`other`, and `tolerated`, which is empty. es9-daemon is held to all four.

### Tolerated: nothing

Until 2026-11-14 Architeuthis's `Tidal/OSC.erl` chose each type tag from
the Erlang value it was handed, so a level or a length that happened to be
a whole number went out tagged as an integer, and es9-daemon read any
number for any argument. Architeuthis now sends through the descriptions
(`rig_wire.erl`), and those three packets are in `refused`.

### Read by the daemon, sent by nothing

`/esx/enable`, `/tidal/gate`, `/tidal/cv` and `/tidal/cv/slew` have no
sender anywhere on the rig. They are declared because the daemon reads
them. They are candidates for removal.

## Who writes, and who reads

es9-daemon, the one reader, replays all four parts in `cargo test`
(`osc_tests`).

| Program | Language | Sends | Held by |
|---|---|---|---|
| Architeuthis (`rig_wire.erl`, for `es9_cv.erl`, `Tidal/OSC.erl` and the browser relay in `Handler.erl`) | Erlang, encoding with the descriptions themselves | `/cv`, `/cv/slew`, `/cv/trig`, `/cv/trig/at`, `/tidal/gate/trig`, `/esx`, `/esx5gate` | `make test-erl` (`rig_wire_tests`) |
| DeepStar (`internal/rig/osc.go`) | Go | `/cv`, `/cv/trig`, `/esx` | `go test ./internal/rig` (`wire_test.go`) |
| Friends server (`server.mjs`) | JavaScript | `/cv`, `/cv/trig`, `/cv/trig/at`, `/esx`, `/esx5gate` | `node conformance/wire.mjs`, against the real server |
| Diaphus (`--debug-beat` only) | Rust | `/cv/trig/at` | not yet |

## Conforming

As for Diaphus. The file carries `"es9-osc-vectors": 1`.

## Changing this

Change this document, then `test/Test/Daemons.purs`, whose cases are written
by hand, then the descriptions until `make test` passes, then `make vectors`.
