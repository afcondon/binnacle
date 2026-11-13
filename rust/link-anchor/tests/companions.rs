//! Replays `conformance/vectors/link-peers.json` and
//! `conformance/vectors/clock-origin.json` against this crate: decoding
//! every case, and encoding for the accepted ones.
//!
//! The files are compiled in with `include_str!`, so a missing file is a
//! build failure, not a skipped test.

use link_anchor::{origin, peers};
use serde_json::Value;

fn vectors(text: &str, version: &str) -> Vec<Value> {
    let json: Value = serde_json::from_str(text).expect("the vector file is JSON");
    assert_eq!(json[version], 1, "a vector format this replayer understands");
    let cases = json["osc"].as_array().expect("an osc section").clone();
    assert!(!cases.is_empty(), "osc is empty: nothing would be tested");
    cases
}

fn bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
        .step_by(2)
        .map(|at| u8::from_str_radix(&hex[at..at + 2], 16).expect("hex"))
        .collect()
}

#[test]
fn peers_cases_decode_to_their_declared_verdict_and_encode_back() {
    let text = include_str!("../../../conformance/vectors/link-peers.json");
    let (mut failures, mut encoded) = (Vec::new(), 0);
    for case in vectors(text, "link-peers-vectors") {
        let name = case["name"].as_str().expect("name");
        let expect = case["expect"].as_str().expect("expect");
        let packet = bytes(case["hex"].as_str().expect("hex"));
        let arrival = peers::decode(&packet);
        let verdict = match arrival {
            peers::Arrival::Accept(_) => "accept",
            peers::Arrival::Refuse(_) => "refuse",
            peers::Arrival::Other => "other",
        };
        if verdict != expect {
            failures.push(format!("{name}: vector says {expect}, decode gave {arrival:?}"));
            continue;
        }
        if let peers::Arrival::Accept(count) = arrival {
            let declared = case["peers"].as_u64().expect("peers");
            if u64::from(count) != declared {
                failures.push(format!("{name}: decoded {count}, vector says {declared}"));
            }
            if peers::encode(declared).to_vec() != packet {
                failures.push(format!("{name}: encoding {declared} does not give the packet"));
            }
            encoded += 1;
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
    assert!(encoded > 0, "no accepted cases: the encoder was not tested");
}

#[test]
fn a_count_past_the_maximum_is_sent_as_the_maximum() {
    assert_eq!(peers::encode(u64::MAX), peers::encode(peers::PEERS_MAXIMUM));
    assert_eq!(peers::decode(&peers::encode(u64::MAX)), peers::Arrival::Accept(i32::MAX as u32));
}

#[test]
fn origin_cases_decode_to_their_declared_verdict_and_encode_back() {
    let text = include_str!("../../../conformance/vectors/clock-origin.json");
    let (mut failures, mut encoded) = (Vec::new(), 0);
    for case in vectors(text, "clock-origin-vectors") {
        let name = case["name"].as_str().expect("name");
        let expect = case["expect"].as_str().expect("expect");
        let packet = bytes(case["hex"].as_str().expect("hex"));
        let arrival = origin::decode(&packet);
        let verdict = match arrival {
            origin::Arrival::Accept(_) => "accept",
            origin::Arrival::Refuse(_) => "refuse",
            origin::Arrival::Other => "other",
        };
        if verdict != expect {
            failures.push(format!("{name}: vector says {expect}, decode gave {arrival:?}"));
            continue;
        }
        if let origin::Arrival::Accept(beat) = arrival {
            let declared = case["beat"].as_f64().expect("beat");
            if beat != declared {
                failures.push(format!("{name}: decoded {beat}, vector says {declared}"));
            }
            if origin::encode(declared).map(|packet| packet.to_vec()) != Ok(packet) {
                failures.push(format!("{name}: encoding {declared} does not give the packet"));
            }
            encoded += 1;
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
    assert!(encoded > 0, "no accepted cases: the encoder was not tested");
}

#[test]
fn a_producer_cannot_encode_a_non_finite_origin() {
    assert_eq!(origin::encode(f64::NAN), Err(origin::Refusal::NonFiniteValue));
    assert_eq!(origin::encode(f64::INFINITY), Err(origin::Refusal::NonFiniteValue));
}
