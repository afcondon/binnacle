# link-anchor

`/link/anchor` for Rust: the value, its validity rule, the 56-byte OSC
packet and the beat extrapolation. No dependencies.

The declaration is `../../conformance/LINK-ANCHOR.md`. This crate is held
to `../../conformance/vectors/link-anchor.json` by `tests/conformance.rs`;
run `cargo test` here.

```rust
use link_anchor::{decode, Arrival};

match decode(&datagram) {
    Arrival::Accept(anchor) => { /* hold it; note when it arrived */ }
    Arrival::Refuse(_) => { /* count it */ }
    Arrival::Other => { /* another message; dispatch or ignore */ }
}
```

A producer builds an `Anchor` with `Anchor::new`, which applies the rule,
and sends `anchor.encode()`.

## Depending on it

Diaphus, es9-daemon and Itajara take it from git at a pinned commit, so that
each of those repositories builds from a lone clone:

```toml
link-anchor = { git = "https://github.com/afcondon/binnacle", rev = "<commit>" }
```

Cargo finds the crate inside the repository by its package name. After a
change here, push Binnacle and move the `rev` in each of the three.
