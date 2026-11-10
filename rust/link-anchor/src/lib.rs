//! `/link/anchor`: the one message that tells every program on the rig where
//! the beat is.
//!
//! The declaration is `conformance/LINK-ANCHOR.md` in this repository, and
//! the reference implementation is `Binnacle.Anchor` (PureScript). This crate
//! is the Rust implementation, held to the same vector file by
//! `tests/conformance.rs`. It exists so that the producer (Diaphus) and the
//! Rust receivers (es9-daemon, Itajara) share one copy of the rule rather
//! than each writing their own.
//!
//! What is here: the value, the validity rule, the OSC packet, and the
//! extrapolation. What is not: sockets, clocks, or any record of when an
//! anchor arrived. Those belong to the program that uses it.

/// Lowest tempo accepted, in beats per minute. Link's own floor.
pub const TEMPO_MINIMUM: f64 = 20.0;
/// Highest tempo accepted. Link's own ceiling.
pub const TEMPO_MAXIMUM: f64 = 999.0;
/// Fewest beats in a bar.
pub const QUANTUM_MINIMUM: f64 = 1.0;
/// Most beats in a bar.
pub const QUANTUM_MAXIMUM: f64 = 64.0;
/// 2^53. `unix_micros` must be below it, so that every implementation,
/// including those that keep time in a double, holds it exactly.
pub const UNIX_MICROS_MAXIMUM: i64 = 1 << 53;
/// An anchor drives the clock until this long after it was received,
/// inclusive.
pub const FRESH_FOR_MICROS: u64 = 2_000_000;
/// How often the producer publishes: 10 Hz.
pub const PUBLISH_PERIOD_MICROS: u64 = 100_000;
/// The whole datagram: 16 bytes of address, 8 of type tags, 32 of arguments.
pub const PACKET_LENGTH: usize = 56;

/// `/link/anchor`, NUL-terminated and padded to a multiple of four.
const ADDRESS: &[u8; 16] = b"/link/anchor\0\0\0\0";
/// `,hddd`, the same.
const TYPE_TAGS: &[u8; 8] = b",hddd\0\0\0";

/// The affine map from wall clock to Link's beat grid.
///
/// The fields are private so that an `Anchor` is always a valid one: the
/// only ways to get one are [`Anchor::new`] and [`decode`], and both apply
/// the rule.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Anchor {
    unix_micros: i64,
    beat: f64,
    tempo: f64,
    quantum: f64,
}

/// Why something is not an anchor we will use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// Our address, but the type tags are not exactly `,hddd`.
    WrongTypeTags,
    /// Our address and tags, but the datagram is not exactly 56 bytes.
    WrongLength,
    /// `beat`, `tempo` or `quantum` is NaN or infinite.
    NonFiniteValue,
    /// `unix_micros` is negative or at least 2^53.
    UnixMicrosOutOfRange,
    /// `tempo` is outside 20 to 999.
    TempoOutOfRange,
    /// `quantum` is outside 1 to 64.
    QuantumOutOfRange,
}

impl Refusal {
    /// The name the declaration and the vector file use.
    pub fn name(self) -> &'static str {
        match self {
            Refusal::WrongTypeTags => "wrong-type-tags",
            Refusal::WrongLength => "wrong-length",
            Refusal::NonFiniteValue => "non-finite-value",
            Refusal::UnixMicrosOutOfRange => "unix-micros-out-of-range",
            Refusal::TempoOutOfRange => "tempo-out-of-range",
            Refusal::QuantumOutOfRange => "quantum-out-of-range",
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
    /// A valid anchor. Replace the held one and note when this arrived.
    Accept(Anchor),
    /// Meant to be an anchor, and not usable. Keep the held one and COUNT
    /// this: a listener hearing bad anchors must not look like one hearing
    /// nothing.
    Refuse(Refusal),
    /// Never an anchor: another OSC address, a bundle, or too short to say.
    /// Dispatch it elsewhere or ignore it; do not count it.
    Other,
}

impl Anchor {
    /// An anchor from its four values, if they satisfy the validity rule.
    ///
    /// Finiteness is checked before range. A NaN is neither inside nor
    /// outside a range, so a range test alone would let one through
    /// whichever way it happened to be written.
    pub fn new(unix_micros: i64, beat: f64, tempo: f64, quantum: f64) -> Result<Anchor, Refusal> {
        if !(0..UNIX_MICROS_MAXIMUM).contains(&unix_micros) {
            return Err(Refusal::UnixMicrosOutOfRange);
        }
        if !(beat.is_finite() && tempo.is_finite() && quantum.is_finite()) {
            return Err(Refusal::NonFiniteValue);
        }
        if !(TEMPO_MINIMUM..=TEMPO_MAXIMUM).contains(&tempo) {
            return Err(Refusal::TempoOutOfRange);
        }
        if !(QUANTUM_MINIMUM..=QUANTUM_MAXIMUM).contains(&quantum) {
            return Err(Refusal::QuantumOutOfRange);
        }
        Ok(Anchor { unix_micros, beat, tempo, quantum })
    }

    /// When the map was sampled: microseconds since the Unix epoch.
    pub fn unix_micros(&self) -> i64 {
        self.unix_micros
    }

    /// Link's beat at that moment. May be negative.
    pub fn beat(&self) -> f64 {
        self.beat
    }

    /// Beats per minute.
    pub fn tempo(&self) -> f64 {
        self.tempo
    }

    /// Beats per bar.
    pub fn quantum(&self) -> f64 {
        self.quantum
    }

    /// Link's beat at a wall-clock moment, in microseconds since the epoch.
    ///
    /// The operations are in the declaration's order: subtract, multiply by
    /// tempo, divide by sixty million, add.
    pub fn beat_at(&self, unix_micros: f64) -> f64 {
        self.beat + (unix_micros - self.unix_micros as f64) * self.tempo / 60_000_000.0
    }

    /// The datagram a producer sends.
    pub fn encode(&self) -> [u8; PACKET_LENGTH] {
        let mut packet = [0u8; PACKET_LENGTH];
        packet[..16].copy_from_slice(ADDRESS);
        packet[16..24].copy_from_slice(TYPE_TAGS);
        packet[24..32].copy_from_slice(&self.unix_micros.to_be_bytes());
        packet[32..40].copy_from_slice(&self.beat.to_be_bytes());
        packet[40..48].copy_from_slice(&self.tempo.to_be_bytes());
        packet[48..56].copy_from_slice(&self.quantum.to_be_bytes());
        packet
    }
}

/// Read one UDP datagram.
pub fn decode(packet: &[u8]) -> Arrival {
    if packet.len() < ADDRESS.len() || packet[..16] != ADDRESS[..] {
        return Arrival::Other;
    }
    if packet.len() < 24 || packet[16..24] != TYPE_TAGS[..] {
        return Arrival::Refuse(Refusal::WrongTypeTags);
    }
    if packet.len() != PACKET_LENGTH {
        return Arrival::Refuse(Refusal::WrongLength);
    }
    let eight = |at: usize| -> [u8; 8] {
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&packet[at..at + 8]);
        bytes
    };
    match Anchor::new(
        i64::from_be_bytes(eight(24)),
        f64::from_be_bytes(eight(32)),
        f64::from_be_bytes(eight(40)),
        f64::from_be_bytes(eight(48)),
    ) {
        Ok(anchor) => Arrival::Accept(anchor),
        Err(refusal) => Arrival::Refuse(refusal),
    }
}

/// Whether an anchor received `age_micros` ago still drives the clock.
pub fn is_fresh(age_micros: u64) -> bool {
    age_micros <= FRESH_FOR_MICROS
}
