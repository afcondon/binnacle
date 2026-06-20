# Binnacle

A reusable client SDK for browser apps that sync to the **Atlantis**
live-coding rig. The binnacle is the deck housing that holds a ship's
navigation instruments steady; this one holds the three instruments any
Atlantis-synced app needs:

1. **A Link-locked clock** that free-runs at a fallback tempo until the
   rig's anchor arrives, then phase-locks to it. The app always just
   reads `beat`/`bar`/`phase`; whether it's `locked` depends only on
   whether the rig is forwarding an anchor — so the *same code* is the
   solo (free-run) and the ensemble (Link-locked) story.
2. **A lookahead scheduler** that walks a beat grid ahead of the clock
   and hands each step its exact fire-time, so audio and UI derive from
   one clock and stay locked despite browser-timer jitter.
3. **Direct sample-accurate output** to es9-daemon (gates + CV), with a
   1V/oct note→volts helper.

Triggerfish (#240) is the first consumer; Calypso (#192) could adopt the
clock half for a synced playhead.

## Usage

```purescript
import Binnacle as Binnacle
import Binnacle.Clock as Clock
import Binnacle.Output as Output
import Binnacle.Scheduler as Scheduler

main = do
  bin <- Binnacle.connect { url: "ws://127.0.0.1:3012/ws", tempo: 120.0 }

  -- read the clock anywhere (e.g. per animation frame)
  r <- Clock.read (Binnacle.clock bin)   -- { beat, bar, phase, tempo, quantum, locked }

  -- schedule a 16th-note grid; fire audio + record visuals on the same beat-times
  cancel <- Scheduler.startGrid (Binnacle.clock bin)
              { stepBeats: 0.25, lookaheadMs: 120.0, tickMs: 25 }
              \tick -> do
                 Output.cvOut  (Binnacle.socket bin) { bus: 12, value: Output.voct Output.defaultTuning 60 }
                 Output.fireAt (Binnacle.socket bin) { bus: 8, value: 0.5, durMs: 40.0, delayMs: tick.delayMs }
```

`connect` opens the WebSocket, subscribes to the anchor on open, and
feeds incoming anchors into the clock. The clock degrades gracefully: if
the rig is down the socket just never opens, sends are dropped, and the
clock free-runs — so an app built on Binnacle runs standalone too.

## The Atlantis Sync Protocol

Line-oriented text frames over the rig WebSocket (`ws://<host>:3012/ws`,
served today by purerl-tidal). Implemented server-side by purerl-tidal's
`tidal_link_anchor` (anchor forwarding) and WS handler (output relay);
the implementation can move into es9-daemon later without changing apps.

### server → client

| Frame | Meaning |
|-------|---------|
| `anchor <unixMicros> <beat> <tempo> <quantum>` | The Ableton Link affine map, forwarded ~10 Hz once subscribed. `unixMicros` is the int64 wall-clock timestamp; extrapolate `beat(t) = beat + (t − unixMicros)·tempo/60e6`. The browser maps host-time via `Date.now()` (same wall clock on the rig host — no NTP handshake). |

### client → server

| Verb | Effect |
|------|--------|
| `clock-subscribe` | Start receiving `anchor` frames on this connection (opt-in, so Calypso et al. on the same socket are unaffected). |
| `fire-at <bus> <val> <durMs> <delayMs>` | Schedule a sample-accurate trigger: es9 bus held at `val` for `durMs`, firing `delayMs` from receipt (relayed as OSC `/cv/trig/at`). |
| `cv-out <bus> <val>` | Set a CV bus immediately, e.g. pitch ahead of a gate (OSC `/cv`). |
| `cv-slew <bus> <val> <lagSec>` | Set a CV bus with a glide (OSC `/cv/slew`). |

`bus` is an es9-daemon bus 0–15 (panel jacks 1–8 are buses 8–15); `val`
is normalized −1.0…+1.0 = ±10 V.

## Why scheduled, not fire-now

The rig has no "fire this instant" verb on purpose. Browser timers jitter
and throttle; es9-daemon's CoreAudio clock does not. So Binnacle computes
*when* each event should sound and schedules it slightly ahead via
`fire-at`'s `delayMs` — es9-daemon fires it sample-accurately. Browser
jitter can't bite the audio as long as it stays within the lookahead
window. The app draws each event at the same computed fire-time, so the
visual onset lands on the audio onset.
