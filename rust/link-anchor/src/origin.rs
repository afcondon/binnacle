//! `/clock/origin`: the beat that clock divisions count from.
//!
//! The declaration is `conformance/CLOCK-ORIGIN.md`; this is held to
//! `conformance/vectors/clock-origin.json` by `tests/companions.rs`. Diaphus
//! is the producer and es9-daemon the receiver, so both ends of this wire
//! are this one module.

/// The whole datagram: 16 bytes of address, 4 of type tags, 8 of argument.
pub const PACKET_LENGTH: usize = 28;

/// `/clock/origin`, NUL-terminated and padded to a multiple of four.
const ADDRESS: &[u8; 16] = b"/clock/origin\0\0\0";
/// `,d`, the same.
const TYPE_TAGS: &[u8; 4] = b",d\0\0";

/// Why something addressed to `/clock/origin` is not an origin we will use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// Our address, but the type tags are not exactly `,d`.
    WrongTypeTags,
    /// Our address and tags, but the datagram is not exactly 28 bytes.
    WrongLength,
    /// The beat is NaN or infinite.
    NonFiniteValue,
}

impl Refusal {
    /// The name the declaration and the vector file use.
    pub fn name(self) -> &'static str {
        match self {
            Refusal::WrongTypeTags => "wrong-type-tags",
            Refusal::WrongLength => "wrong-length",
            Refusal::NonFiniteValue => "non-finite-value",
        }
    }
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name())
    }
}

/// What a receiver does with one datagram.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Arrival {
    /// A finite beat. Replace the held origin.
    Accept(f64),
    /// Meant to be an origin, and not usable. Keep the held one and count
    /// this.
    Refuse(Refusal),
    /// Never this message.
    Other,
}

/// The datagram a producer sends, if the beat is finite. A producer sends
/// nothing else.
pub fn encode(beat: f64) -> Result<[u8; PACKET_LENGTH], Refusal> {
    if !beat.is_finite() {
        return Err(Refusal::NonFiniteValue);
    }
    let mut packet = [0u8; PACKET_LENGTH];
    packet[..16].copy_from_slice(ADDRESS);
    packet[16..20].copy_from_slice(TYPE_TAGS);
    packet[20..28].copy_from_slice(&beat.to_be_bytes());
    Ok(packet)
}

/// Read one UDP datagram.
pub fn decode(packet: &[u8]) -> Arrival {
    if packet.len() < ADDRESS.len() || packet[..16] != ADDRESS[..] {
        return Arrival::Other;
    }
    if packet.len() < 20 || packet[16..20] != TYPE_TAGS[..] {
        return Arrival::Refuse(Refusal::WrongTypeTags);
    }
    if packet.len() != PACKET_LENGTH {
        return Arrival::Refuse(Refusal::WrongLength);
    }
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&packet[20..28]);
    let beat = f64::from_be_bytes(bytes);
    if beat.is_finite() {
        Arrival::Accept(beat)
    } else {
        Arrival::Refuse(Refusal::NonFiniteValue)
    }
}
