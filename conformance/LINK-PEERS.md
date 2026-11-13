# `/link/peers` — the declaration

How many other Link peers share the session. Diaphus sends it to
Architeuthis, which passes it to the Dashboard.

`test/Reference/LinkPeers.purs` is the reference implementation.
`conformance/vectors/link-peers.json` is the set of cases every
implementation replays. Declared 2026-11-13, in the manner of
`LINK-ANCHOR.md`, which this file follows wherever it says nothing.

## The value

One whole number: the count of *other* peers. Zero means Diaphus is alone on
the session.

## Validity

`0 <= peers <= 2147483647`. A producer with a larger count sends the maximum.

## When it is sent

When the count changes, and once a second regardless, so a receiver that has
just started has it within a second.

## The packet

One bare OSC message per datagram. Exactly 20 bytes:

| Bytes | Content |
|---|---|
| 0–11 | `/link/peers`, a NUL |
| 12–15 | `,i`, two NULs |
| 16–19 | `peers`, big-endian signed 32-bit integer |

## The verdict

1. If the first 12 bytes are not the address above, the verdict is `other`.
2. Otherwise, if bytes 12–15 are not exactly the type tags above, or the
   datagram is not exactly 20 bytes, the verdict is `refuse`.
3. Otherwise, if the integer is negative, the verdict is `refuse`.
4. Otherwise `accept`.

A refusal is counted, in the same count as refused anchors: it is the count
of messages from Diaphus that this receiver could not use.

## Who holds a copy

| Program | Language | Role | Port | Held by |
|---|---|---|---|---|
| Diaphus | Rust | producer | sends to 57121 | the `link-anchor` crate |
| Architeuthis (`tidal_link_anchor.erl`) | Erlang | receiver | 57121 | `make test-erl` |

## Conforming

Replay `osc` in the vector file: decode `hex`; the verdict must equal
`expect`; when accepted, the count must equal `peers`. A producer is held to
the accepted cases: encoding `peers` must give `hex` byte for byte.

The file carries `"link-peers-vectors": 1`. A replayer asserts the number it
understands. Not finding the file is a failure, not a skip.

## Changing this

Change this document, then `test/Test/Companions.purs`, whose verdicts are
written by hand, then the reference until `make test` passes, then
`make vectors`.
