#!/usr/bin/env python3
"""Replays the Diaphus-inbound and es9-daemon OSC vectors.

A second implementation, written from DIAPHUS-INBOUND.md and ES9-OSC.md and
sharing no code with the PureScript reference: a strict reader and a writer
for every declared message. Not finding a vector file is a failure.
"""
import json
import math
import pathlib
import struct
import sys

HERE = pathlib.Path(__file__).parent / "vectors"


def osc_string(text):
    raw = text.encode("utf-8") + b"\0"
    return raw + b"\0" * ((4 - len(raw) % 4) % 4)


def within(low, high):
    return lambda value: low <= value <= high


def finite(value):
    return math.isfinite(value)


def not_negative(value):
    return math.isfinite(value) and value >= 0


def anything(_value):
    return True


CHANNEL, SEVEN, FLAG, BUS, EIGHTH, QUARTER = within(1, 16), within(0, 127), within(0, 1), within(0, 15), within(0, 7), within(0, 3)

# address -> (type tags, one rule per argument), from the two documents.
DIAPHUS = {
    "/midi/note/at": ("siiiih", [anything, CHANNEL, SEVEN, SEVEN, not_negative, not_negative]),
    "/midi/on/at": ("siiih", [anything, CHANNEL, SEVEN, SEVEN, not_negative]),
    "/midi/off/at": ("siih", [anything, CHANNEL, SEVEN, not_negative]),
    "/midi/cc/at": ("siiih", [anything, CHANNEL, SEVEN, SEVEN, not_negative]),
    "/link/set-tempo": ("d", [lambda bpm: math.isfinite(bpm) and 20 <= bpm <= 999]),
    "/link/play": ("i", [FLAG]),
    "/clock/restart": ("", []),
}
ES9 = {
    "/cv": ("if", [BUS, finite]),
    "/cv/slew": ("iff", [BUS, finite, not_negative]),
    "/cv/trig": ("iff", [BUS, finite, not_negative]),
    "/cv/trig/at": ("ifff", [BUS, finite, not_negative, not_negative]),
    "/esx": ("if", [EIGHTH, finite]),
    "/esx5gate": ("ii", [EIGHTH, FLAG]),
    "/esx/enable": ("i", [FLAG]),
    "/tidal/gate/trig": ("if", [EIGHTH, not_negative]),
    "/tidal/gate": ("ii", [EIGHTH, FLAG]),
    "/tidal/cv": ("if", [QUARTER, finite]),
    "/tidal/cv/slew": ("iff", [QUARTER, finite, not_negative]),
}
FORMATS = {"i": ">i", "f": ">f", "d": ">d", "h": ">q"}


def encode(table, address, values):
    tags, _rules = table[address]
    out = osc_string(address) + osc_string("," + tags)
    for tag, value in zip(tags, values):
        out += osc_string(value) if tag == "s" else struct.pack(FORMATS[tag], value)
    return out


def decode(table, packet):
    """('accept', address, values), ('refuse',), or ('other',)."""
    for address, (tags, rules) in table.items():
        head = osc_string(address)
        if packet[: len(head)] != head:
            continue
        header = head + osc_string("," + tags)
        if packet[: len(header)] != header:
            return ("refuse",)
        at, values = len(header), []
        for tag in tags:
            if tag == "s":
                end = packet.find(b"\0", at)
                if end < 0:
                    return ("refuse",)
                stop = at + (end - at + 4) // 4 * 4
                if stop > len(packet) or any(packet[end:stop]):
                    return ("refuse",)
                try:
                    values.append(packet[at:end].decode("utf-8"))
                except UnicodeDecodeError:
                    return ("refuse",)
                at = stop
            else:
                size = struct.calcsize(FORMATS[tag])
                if at + size > len(packet):
                    return ("refuse",)
                values.append(struct.unpack(FORMATS[tag], packet[at : at + size])[0])
                at += size
        if at != len(packet):
            return ("refuse",)
        if tags.endswith("h") and abs(values[-1]) >= 2**53:
            return ("refuse",)
        if not all(rule(value) for rule, value in zip(rules, values)):
            return ("refuse",)
        return ("accept", address, values)
    return ("other",)


failures, counts = [], []
for file, version, table in (
    ("diaphus-inbound.json", "diaphus-inbound-vectors", DIAPHUS),
    ("es9-osc.json", "es9-osc-vectors", ES9),
):
    vectors = json.loads((HERE / file).read_text())
    assert vectors[version] == 1, f"{file}: unknown vector format"
    assert vectors["packets"], f"{file}: no packets, nothing would be tested"
    declared = {m["address"]: m["tags"] for m in vectors["messages"]}
    if declared != {address: tags for address, (tags, _) in table.items()}:
        failures.append(f"{file}: the messages listed are not the ones this replayer knows")
    for case in vectors["packets"]:
        packet = bytes.fromhex(case["hex"])
        label = f"{file}/packets/{case['name']}"
        if decode(table, packet) != ("accept", case["address"], case["values"]):
            failures.append(f"{label}: read as {decode(table, packet)}")
        if encode(table, case["address"], case["values"]) != packet:
            failures.append(f"{label}: writing the values does not give the packet")
    for case in vectors["refused"] + vectors["tolerated"]:
        if decode(table, bytes.fromhex(case["hex"])) != ("refuse",):
            failures.append(f"{file}/{case['name']}: a strict reader must refuse this")
    for case in vectors["other"]:
        if decode(table, bytes.fromhex(case["hex"])) != ("other",):
            failures.append(f"{file}/other/{case['name']}: this is nobody's message here")
    counts.append(f"{len(vectors['packets'])} packets, {len(vectors['refused'])} refused, {len(vectors['tolerated'])} tolerated, {len(vectors['other'])} other")

for failure in failures:
    print("FAIL ", failure)
print(f"daemons: {'; '.join(counts)}; {len(failures)} failures")
sys.exit(1 if failures else 0)
