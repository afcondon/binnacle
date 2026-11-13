#!/usr/bin/env python3
"""Replays the /link/peers and /clock/origin vectors.

A second implementation of each, written from LINK-PEERS.md and
CLOCK-ORIGIN.md and sharing no code with the PureScript references.
Not finding a vector file is a failure, not a skip.
"""
import json
import math
import pathlib
import struct
import sys

HERE = pathlib.Path(__file__).parent / "vectors"


def decode(packet, address, tags, layout, valid):
    """The verdict and, when accepted, the value."""
    if packet[: len(address)] != address:
        return "other", None
    header = address + tags
    if packet[: len(header)] != header or len(packet) != len(header) + struct.calcsize(layout):
        return "refuse", None
    (value,) = struct.unpack(layout, packet[len(header):])
    return ("accept", value) if valid(value) else ("refuse", None)


def decode_peers(packet):
    return decode(packet, b"/link/peers\0", b",i\0\0", ">i", lambda peers: peers >= 0)


def decode_origin(packet):
    return decode(packet, b"/clock/origin\0\0\0", b",d\0\0", ">d", math.isfinite)


failures = []
counts = []
for file, version, key, decoder in (
    ("link-peers.json", "link-peers-vectors", "peers", decode_peers),
    ("clock-origin.json", "clock-origin-vectors", "beat", decode_origin),
):
    vectors = json.loads((HERE / file).read_text())
    assert vectors[version] == 1, f"{file}: unknown vector format"
    assert vectors["osc"], f"{file}: no cases, nothing would be tested"
    for case in vectors["osc"]:
        verdict, got = decoder(bytes.fromhex(case["hex"]))
        label = f"{key}/{case['name']}"
        if verdict != case["expect"]:
            failures.append(f"{label}: vector says {case['expect']}, this says {verdict}")
        elif verdict == "accept" and got != case[key]:
            failures.append(f"{label}: decoded {got!r}, vector says {case[key]!r}")
    counts.append(f"{len(vectors['osc'])} {key}")

for failure in failures:
    print("FAIL ", failure)
print(f"{', '.join(counts)}; {len(failures)} failures")
sys.exit(1 if failures else 0)
