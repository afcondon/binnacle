//! Reading one OSC message strictly: an address, its exact type tags, and
//! arguments that end exactly where the datagram does.
//!
//! This is the rule `/link/anchor` set, for any message whose arguments are
//! strings (`s`), int32 (`i`), int64 (`h`), binary32 (`f`) and binary64
//! (`d`). It is the Rust counterpart of `Hawser.Osc.decode`, and the two
//! daemons that use it are held to the same vector files as that is
//! (`conformance/vectors/diaphus-inbound.json`, `es9-osc.json`).
//!
//! 1. If the datagram does not begin with the address, it is `Other`:
//!    somebody else's message, not an error, not counted.
//! 2. Otherwise, if the type tags are not exactly the declared ones, it is
//!    refused as `wrong-type-tags`; if the arguments do not end exactly at
//!    the end of the datagram, as `wrong-length`.
//! 3. Otherwise the arguments are returned. Rules on their values (a
//!    range, finiteness) are the caller's, and it refuses with their tags.
//!
//! A bundle is never one of these messages, so it is `Other`.

/// One argument, as its type tag says.
#[derive(Clone, Debug, PartialEq)]
pub enum Argument {
    Text(String),
    Int(i32),
    Long(i64),
    Float(f32),
    Double(f64),
}

/// What one datagram is, as one declared message.
#[derive(Clone, Debug, PartialEq)]
pub enum Read {
    /// This message, well formed. The arguments, in order.
    Accept(Vec<Argument>),
    /// Addressed to this message and not usable. The tag says why.
    Refuse(&'static str),
    /// Never this message.
    Other,
}

/// The type tags are not exactly the declared ones.
pub const WRONG_TYPE_TAGS: &str = "wrong-type-tags";
/// The arguments do not end exactly where the datagram does.
pub const WRONG_LENGTH: &str = "wrong-length";
/// A string argument is not UTF-8.
pub const MALFORMED_STRING: &str = "malformed-string";

/// An OSC string: the bytes, a NUL, then NULs to a multiple of four.
fn padded(text: &str) -> Vec<u8> {
    let mut bytes = text.as_bytes().to_vec();
    bytes.push(0);
    while bytes.len() % 4 != 0 {
        bytes.push(0);
    }
    bytes
}

/// Read `packet` as the message at `address` whose type tags, without the
/// comma, are `tags`.
pub fn read(packet: &[u8], address: &str, tags: &str) -> Read {
    let address_bytes = padded(address);
    if !packet.starts_with(&address_bytes) {
        return Read::Other;
    }
    let tag_bytes = padded(&format!(",{tags}"));
    let mut at = address_bytes.len();
    if !packet[at..].starts_with(&tag_bytes) {
        return Read::Refuse(WRONG_TYPE_TAGS);
    }
    at += tag_bytes.len();

    // Where each argument ends, before reading any: a datagram of the wrong
    // length is refused for its length, whatever its values are.
    let mut ends = Vec::with_capacity(tags.len());
    let mut end = at;
    for tag in tags.bytes() {
        end = match tag {
            b'i' | b'f' => end + 4,
            b'h' | b'd' => end + 8,
            b's' => match packet.get(end..).and_then(|rest| rest.iter().position(|&byte| byte == 0)) {
                Some(terminator) => end + (terminator + 4) / 4 * 4,
                None => return Read::Refuse(WRONG_LENGTH),
            },
            other => panic!("strict::read: a type tag it does not read: {}", other as char),
        };
        if end > packet.len() {
            return Read::Refuse(WRONG_LENGTH);
        }
        ends.push(end);
    }
    if end != packet.len() {
        return Read::Refuse(WRONG_LENGTH);
    }

    let mut arguments = Vec::with_capacity(tags.len());
    for (tag, end) in tags.bytes().zip(ends) {
        let bytes = &packet[at..end];
        arguments.push(match tag {
            b'i' => Argument::Int(i32::from_be_bytes(bytes.try_into().expect("four bytes"))),
            b'f' => Argument::Float(f32::from_be_bytes(bytes.try_into().expect("four bytes"))),
            b'h' => Argument::Long(i64::from_be_bytes(bytes.try_into().expect("eight bytes"))),
            b'd' => Argument::Double(f64::from_be_bytes(bytes.try_into().expect("eight bytes"))),
            _ => {
                let terminator = bytes.iter().position(|&byte| byte == 0).expect("found above");
                match std::str::from_utf8(&bytes[..terminator]) {
                    Ok(text) => Argument::Text(text.to_string()),
                    Err(_) => return Read::Refuse(MALFORMED_STRING),
                }
            }
        });
        at = end;
    }
    Read::Accept(arguments)
}

/// Read `packet` as one of several declared messages, each an address and
/// its type tags: the first that does not say `Other`, with its address.
pub fn read_any<'a>(packet: &[u8], messages: &[(&'a str, &'a str)]) -> (&'a str, Read) {
    for (address, tags) in messages {
        match read(packet, address, tags) {
            Read::Other => continue,
            read => return (address, read),
        }
    }
    ("", Read::Other)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_cv() {
        let packet = [b"/cv\0,if\0".as_slice(), &8i32.to_be_bytes(), &0.5f32.to_be_bytes()].concat();
        assert_eq!(read(&packet, "/cv", "if"), Read::Accept(vec![Argument::Int(8), Argument::Float(0.5)]));
        assert_eq!(read(&packet, "/cv", "ii"), Read::Refuse(WRONG_TYPE_TAGS));
        assert_eq!(read(&packet[..15], "/cv", "if"), Read::Refuse(WRONG_LENGTH));
        assert_eq!(read(&[packet.as_slice(), &[0]].concat(), "/cv", "if"), Read::Refuse(WRONG_LENGTH));
        assert_eq!(read(&packet, "/cv/slew", "iff"), Read::Other);
        assert_eq!(read(&packet, "/c", "if"), Read::Other);
        assert_eq!(read(&[], "/cv", "if"), Read::Other);
    }

    #[test]
    fn a_string_then_a_number() {
        let packet = [b"/x\0\0,si\0FH-2\0\0\0\0".as_slice(), &7i32.to_be_bytes()].concat();
        assert_eq!(read(&packet, "/x", "si"), Read::Accept(vec![Argument::Text("FH-2".into()), Argument::Int(7)]));
        assert_eq!(read(b"/x\0\0,si\0FH-2", "/x", "si"), Read::Refuse(WRONG_LENGTH));
    }

    #[test]
    fn the_first_that_is_not_other() {
        let packet = [b"/cv/slew\0\0\0\0,iff\0\0\0\0".as_slice(), &[0u8; 12]].concat();
        let (address, read) = read_any(&packet, &[("/cv", "if"), ("/cv/slew", "iff")]);
        assert_eq!(address, "/cv/slew");
        assert!(matches!(read, Read::Accept(_)));
    }
}
