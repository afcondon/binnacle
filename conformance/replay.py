#!/usr/bin/env python3
"""Replay the /link/anchor vectors against a second implementation.

This is written from conformance/LINK-ANCHOR.md, not from the PureScript
reference, and shares no code with it. It does two jobs: it is a second
witness that the vector file says what the declaration says, and it is the
shortest example of what "replaying the vectors" means for a port.

    python3 conformance/replay.py            # exits non-zero on any failure
"""
import json
import math
import pathlib
import re
import struct
import sys

HERE = pathlib.Path(__file__).parent
VECTORS = json.loads((HERE / "vectors" / "link-anchor.json").read_text())
C = VECTORS["constants"]

ADDRESS = b"/link/anchor\0\0\0\0"
TAGS = b",hddd\0\0\0"
WHOLE = re.compile(r"^[0-9]+$")
REAL = re.compile(r"^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$")


def valid(micros, beat, tempo, quantum):
    return (
        0 <= micros < C["unixMicrosMaximum"]
        and math.isfinite(beat)
        and math.isfinite(tempo)
        and math.isfinite(quantum)
        and C["tempoMinimum"] <= tempo <= C["tempoMaximum"]
        and C["quantumMinimum"] <= quantum <= C["quantumMaximum"]
    )


def decode_osc(packet):
    """('accept', fields) | ('refuse', None) | ('other', None)"""
    if packet[:16] != ADDRESS:
        return "other", None
    if packet[16:24] != TAGS or len(packet) != C["oscPacketLength"]:
        return "refuse", None
    micros, beat, tempo, quantum = struct.unpack(">qddd", packet[24:])
    if not valid(micros, beat, tempo, quantum):
        return "refuse", None
    return "accept", (micros, beat, tempo, quantum)


def parse_line(line):
    words = line.strip().split(" ")
    if words[0] != "anchor":
        return "other", None
    if len(words) != 5 or not WHOLE.match(words[1]) or not all(REAL.match(w) for w in words[2:]):
        return "refuse", None
    micros, beat, tempo, quantum = int(words[1]), float(words[2]), float(words[3]), float(words[4])
    if not valid(micros, beat, tempo, quantum):
        return "refuse", None
    return "accept", (micros, beat, tempo, quantum)


def beat_at(anchor, at_micros):
    return anchor["beat"] + (at_micros - anchor["unixMicros"]) * anchor["tempo"] / 60000000.0


def fields(anchor):
    return (anchor["unixMicros"], anchor["beat"], anchor["tempo"], anchor["quantum"])


failures = []


def check(section, case, verdict, got):
    label = f"{section}/{case['name']}"
    if verdict != case["expect"]:
        failures.append(f"{label}: vector says {case['expect']}, this says {verdict}")
    elif verdict == "accept" and got != fields(case["anchor"]):
        failures.append(f"{label}: decoded {got}, vector says {fields(case['anchor'])}")


assert VECTORS["link-anchor-vectors"] == 1, "unknown vector format"

for case in VECTORS["osc"]:
    check("osc", case, *decode_osc(bytes.fromhex(case["hex"])))
for case in VECTORS["text"]:
    check("text", case, *parse_line(case["line"]))
for case in VECTORS["beatAt"]:
    got = beat_at(case["anchor"], case["atUnixMicros"])
    if abs(got - case["beat"]) > C["beatTolerance"]:
        failures.append(f"beatAt/{case['name']}: got {got!r}, vector says {case['beat']!r}")
for case in VECTORS["fresh"]:
    if (case["ageMicros"] <= C["freshForMicros"]) != case["fresh"]:
        failures.append(f"fresh/{case['ageMicros']}: vector says {case['fresh']}")

for failure in failures:
    print("FAIL ", failure)
counts = ", ".join(f"{len(VECTORS[k])} {k}" for k in ("osc", "text", "beatAt", "fresh"))
print(f"{counts}; {len(failures)} failures")
sys.exit(1 if failures else 0)
