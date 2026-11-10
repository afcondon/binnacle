//! Replays `conformance/vectors/link-anchor.json` against this crate.
//!
//! Sections replayed: `osc` (decoding, and encoding for the accepted cases),
//! `beatAt`, `fresh`, and the constants. Section skipped, by name: `text`.
//! No Rust program on the rig reads the text frame; it goes from
//! Architeuthis to browsers.

use link_anchor::{decode, is_fresh, Anchor, Arrival};
use serde_json::Value;

fn vectors() -> Value {
    let text = include_str!("../../../conformance/vectors/link-anchor.json");
    let json: Value = serde_json::from_str(text).expect("the vector file is JSON");
    assert_eq!(json["link-anchor-vectors"], 1, "a vector format this replayer understands");
    json
}

fn bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
        .step_by(2)
        .map(|at| u8::from_str_radix(&hex[at..at + 2], 16).expect("hex"))
        .collect()
}

fn cases<'a>(json: &'a Value, section: &str) -> &'a Vec<Value> {
    let found = json[section].as_array().unwrap_or_else(|| panic!("no {section} section"));
    assert!(!found.is_empty(), "{section} is empty: nothing would be tested");
    found
}

fn anchor_of(value: &Value) -> Anchor {
    Anchor::new(
        value["unixMicros"].as_i64().expect("unixMicros"),
        value["beat"].as_f64().expect("beat"),
        value["tempo"].as_f64().expect("tempo"),
        value["quantum"].as_f64().expect("quantum"),
    )
    .expect("an anchor the vector file declares valid")
}

#[test]
fn constants_match_the_vector_file() {
    let json = vectors();
    let constant = |name: &str| json["constants"][name].as_f64().unwrap_or_else(|| panic!("no {name}"));
    assert_eq!(constant("tempoMinimum"), link_anchor::TEMPO_MINIMUM);
    assert_eq!(constant("tempoMaximum"), link_anchor::TEMPO_MAXIMUM);
    assert_eq!(constant("quantumMinimum"), link_anchor::QUANTUM_MINIMUM);
    assert_eq!(constant("quantumMaximum"), link_anchor::QUANTUM_MAXIMUM);
    assert_eq!(constant("unixMicrosMaximum"), link_anchor::UNIX_MICROS_MAXIMUM as f64);
    assert_eq!(constant("freshForMicros"), link_anchor::FRESH_FOR_MICROS as f64);
    assert_eq!(constant("publishPeriodMicros"), link_anchor::PUBLISH_PERIOD_MICROS as f64);
    assert_eq!(constant("oscPacketLength"), link_anchor::PACKET_LENGTH as f64);
}

#[test]
fn osc_cases_decode_to_their_declared_verdict() {
    let json = vectors();
    let mut failures = Vec::new();
    for case in cases(&json, "osc") {
        let name = case["name"].as_str().expect("name");
        let expect = case["expect"].as_str().expect("expect");
        let arrival = decode(&bytes(case["hex"].as_str().expect("hex")));
        let verdict = match arrival {
            Arrival::Accept(_) => "accept",
            Arrival::Refuse(_) => "refuse",
            Arrival::Other => "other",
        };
        if verdict != expect {
            failures.push(format!("{name}: vector says {expect}, decode gave {arrival:?}"));
            continue;
        }
        if let Arrival::Accept(anchor) = arrival {
            let declared = anchor_of(&case["anchor"]);
            if anchor != declared {
                failures.push(format!("{name}: decoded {anchor:?}, vector says {declared:?}"));
            }
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}

#[test]
fn accepted_anchors_encode_to_their_packet() {
    let json = vectors();
    let mut checked = 0;
    for case in cases(&json, "osc") {
        if case["expect"] != "accept" {
            continue;
        }
        let name = case["name"].as_str().expect("name");
        let packet = anchor_of(&case["anchor"]).encode();
        assert_eq!(packet.to_vec(), bytes(case["hex"].as_str().expect("hex")), "{name}");
        checked += 1;
    }
    assert!(checked > 0, "no accepted cases: the encoder was not tested");
}

#[test]
fn beat_at_cases_agree_within_tolerance() {
    let json = vectors();
    let tolerance = json["constants"]["beatTolerance"].as_f64().expect("beatTolerance");
    for case in cases(&json, "beatAt") {
        let name = case["name"].as_str().expect("name");
        let got = anchor_of(&case["anchor"]).beat_at(case["atUnixMicros"].as_f64().expect("atUnixMicros"));
        let want = case["beat"].as_f64().expect("beat");
        assert!((got - want).abs() <= tolerance, "{name}: got {got}, vector says {want}");
    }
}

#[test]
fn fresh_cases_agree() {
    let json = vectors();
    for case in cases(&json, "fresh") {
        let age = case["ageMicros"].as_u64().expect("ageMicros");
        assert_eq!(is_fresh(age), case["fresh"].as_bool().expect("fresh"), "age {age}");
    }
}
