//! `/link/peers`: how many other Link peers share the session.
//!
//! The declaration is `conformance/LINK-PEERS.md`; this is held to
//! `conformance/vectors/link-peers.json` by `tests/companions.rs`. Diaphus is
//! the producer. The receiver is Architeuthis, in Erlang, so `decode` is
//! here for the replay and for any Rust receiver that follows.

/// The whole datagram: 12 bytes of address, 4 of type tags, 4 of argument.
pub const PACKET_LENGTH: usize = 20;
/// The largest count the packet holds. A producer with more sends this.
pub const PEERS_MAXIMUM: u64 = i32::MAX as u64;

/// `/link/peers`, NUL-terminated.
const ADDRESS: &[u8; 12] = b"/link/peers\0";
/// `,i`, NUL-terminated and padded to a multiple of four.
const TYPE_TAGS: &[u8; 4] = b",i\0\0";

/// Why something addressed to `/link/peers` is not a count we will use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// Our address, but the type tags are not exactly `,i`.
    WrongTypeTags,
    /// Our address and tags, but the datagram is not exactly 20 bytes.
    WrongLength,
    /// The count is below zero.
    NegativeCount,
}

/// What a receiver does with one datagram.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Arrival {
    /// A valid count.
    Accept(u32),
    /// Meant to be a count, and not usable. Count it as refused.
    Refuse(Refusal),
    /// Never this message.
    Other,
}

/// The datagram a producer sends. A count past the maximum is sent as the
/// maximum.
pub fn encode(peers: u64) -> [u8; PACKET_LENGTH] {
    let mut packet = [0u8; PACKET_LENGTH];
    packet[..12].copy_from_slice(ADDRESS);
    packet[12..16].copy_from_slice(TYPE_TAGS);
    packet[16..20].copy_from_slice(&(peers.min(PEERS_MAXIMUM) as i32).to_be_bytes());
    packet
}

/// Read one UDP datagram.
pub fn decode(packet: &[u8]) -> Arrival {
    if packet.len() < ADDRESS.len() || packet[..12] != ADDRESS[..] {
        return Arrival::Other;
    }
    if packet.len() < 16 || packet[12..16] != TYPE_TAGS[..] {
        return Arrival::Refuse(Refusal::WrongTypeTags);
    }
    if packet.len() != PACKET_LENGTH {
        return Arrival::Refuse(Refusal::WrongLength);
    }
    let peers = i32::from_be_bytes([packet[16], packet[17], packet[18], packet[19]]);
    match u32::try_from(peers) {
        Ok(peers) => Arrival::Accept(peers),
        Err(_) => Arrival::Refuse(Refusal::NegativeCount),
    }
}
