"use strict";

// The Socket handed to PureScript is a DURABLE HANDLE, not the WebSocket itself.
// It owns a mutable inner `ws` and re-dials when that closes, so callers keep one
// value for the life of the app and never hold a corpse.
//
// Why this matters (2026-08-07): purerl-tidal's cowboy handler sets
// `idle_timeout => 1800000`, and cowboy counts idle from the last frame it
// RECEIVED — anchors flowing rig→browser do not reset it. So a browser sitting
// untouched for 30 minutes gets hung up on. Before this, `onClose` was
// `pure unit` and `send` silently dropped anything written to a closed socket, so
// the whole UI went on looking alive while controlling nothing: leave the rig for
// an hour, come back, and even PANIC did nothing. Same story every morning after
// an overnight, and after every BEAM restart.
//
// Reconnecting here rather than in Binnacle.purs is deliberate: `Binnacle.socket`
// hands callers a concrete Socket, so swapping the connection at a higher level
// would leave every existing holder pointing at the dead one. Doing it inside the
// handle means every machine gets it with no call-site change.
//
// `onOpen` runs on EVERY successful connect, not just the first — which is what
// re-arms the anchor subscription (Binnacle's onOpen sends `clock-subscribe`), so
// the clock comes back by itself after a drop.

const MAX_BACKOFF_MS = 15000;

export const openImpl = (url, handlers) => {
  const handle = { ws: null, stopped: false, tries: 0, timer: null };

  const dial = () => {
    handle.timer = null;
    let ws;
    try {
      ws = new WebSocket(url);
    } catch (e) {
      // Constructor can throw synchronously (bad URL, blocked scheme). Treat it
      // as a failed attempt so the backoff still applies instead of giving up.
      schedule();
      return;
    }
    handle.ws = ws;

    ws.onopen = () => {
      if (handle.tries > 0) console.log("[binnacle] reconnected to " + url);
      handle.tries = 0;
      handlers.onOpen();
    };
    ws.onmessage = (ev) => handlers.onMessage(ev.data);
    ws.onerror = () => {
      // Let onclose drive the retry; closing here guarantees it fires.
      try { ws.close(); } catch (e) { /* already closing */ }
    };
    ws.onclose = () => {
      handlers.onClose();
      if (!handle.stopped) {
        console.warn("[binnacle] socket closed — reconnecting to " + url);
        schedule();
      }
    };
  };

  const schedule = () => {
    if (handle.timer !== null || handle.stopped) return;
    const delay = Math.min(1000 * Math.pow(2, handle.tries), MAX_BACKOFF_MS);
    handle.tries += 1;
    handle.timer = setTimeout(dial, delay);
  };

  dial();
  return handle;
};

// Still a no-op when there is no live connection — a dropped frame is better than
// a thrown exception inside a Halogen handler. The difference now is that the gap
// is seconds rather than permanent, and the console says so.
export const sendImpl = (handle, msg) => {
  const ws = handle.ws;
  if (ws && ws.readyState === 1 /* WebSocket.OPEN */) ws.send(msg);
};

// True while a live connection is up. Lets a surface show whether it is actually
// talking to the rig instead of leaving the user to infer it from silence.
export const isConnectedImpl = (handle) => {
  const ws = handle.ws;
  return !!ws && ws.readyState === 1;
};
