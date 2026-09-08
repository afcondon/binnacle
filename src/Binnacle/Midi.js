"use strict";

export const requestAccessImpl = (cb) => {
  if (!navigator.requestMIDIAccess) { cb(null); return; }
  navigator.requestMIDIAccess({ sysex: false }).then(
    (access) => cb(access),
    () => cb(null)
  );
};

export const outputNamesImpl = (access) => {
  const names = [];
  access.outputs.forEach((o) => names.push(o.name));
  return names;
};

export const findOutputImpl = (access, needle) => {
  let chosen = null;
  access.outputs.forEach((o) => {
    if (chosen) return;
    if (needle === "" || (o.name && o.name.indexOf(needle) >= 0)) chosen = o;
  });
  return chosen;
};

export const inputNamesImpl = (access) => {
  const names = [];
  access.inputs.forEach((i) => names.push(i.name));
  return names;
};

export const findInputImpl = (access, needle) => {
  let chosen = null;
  access.inputs.forEach((i) => {
    if (chosen) return;
    if (needle === "" || (i.name && i.name.indexOf(needle) >= 0)) chosen = i;
  });
  return chosen;
};

// Subscribe to an input's messages. `handler` is an EffectFn3 (a 3-arg JS
// function). We forward the three data bytes; a running-status or malformed
// short message just yields 0s. Returns an unsubscribe that clears the handler
// only if it's still ours (so a re-subscribe doesn't get clobbered).
export const onMessageImpl = (input, handler) => {
  const cb = (ev) => {
    const d = ev.data || [];
    handler(d[0] | 0, d[1] | 0, d[2] | 0);
  };
  input.onmidimessage = cb;
  return () => {
    if (input.onmidimessage === cb) input.onmidimessage = null;
  };
};

// Note-on at now+delayMs, note-off durMs later, via Web MIDI's timestamped
// send — as jitter-immune as the es9 /cv/trig/at path.
export const scheduleNoteImpl = (out, channel, note, velocity, delayMs, durMs) => {
  const ts = performance.now() + Math.max(0, delayMs);
  const ch = channel & 0x0f;
  out.send([0x90 | ch, note & 0x7f, velocity & 0x7f], ts);
  out.send([0x80 | ch, note & 0x7f, 0], ts + Math.max(1, durMs));
};

// Immediate control-change (e.g. portamento on/off + time for glide).
export const sendCCImpl = (out, channel, controller, value) => {
  out.send([0xb0 | (channel & 0x0f), controller & 0x7f, value & 0x7f]);
};

// Note-on / note-off as separate timestamped events, for legato/tie/glide
// where the note-off time isn't known until the next note arrives.
export const noteOnAtImpl = (out, channel, note, velocity, delayMs) => {
  out.send([0x90 | (channel & 0x0f), note & 0x7f, velocity & 0x7f], performance.now() + Math.max(0, delayMs));
};

export const noteOffAtImpl = (out, channel, note, delayMs) => {
  out.send([0x80 | (channel & 0x0f), note & 0x7f, 0], performance.now() + Math.max(0, delayMs));
};

// Absolute-timestamp variants: `atMs` is already a performance.now() timestamp,
// so we DON'T re-read the clock here — the note fires at `atMs` no matter how long
// the pipeline took to reach send(). A past `atMs` fires immediately (so 0.0 = now).
export const scheduleNoteAtMsImpl = (out, channel, note, velocity, atMs, durMs) => {
  const ch = channel & 0x0f;
  out.send([0x90 | ch, note & 0x7f, velocity & 0x7f], atMs);
  out.send([0x80 | ch, note & 0x7f, 0], atMs + Math.max(1, durMs));
};

// A control change on the performance clock rather than at call time. The
// Rample needs its start-point CC to land a fixed lead ahead of the trigger
// note, and under a lookahead scheduler "now" is nowhere near when the note
// sounds — so the CC has to be timestamped exactly as the note is.
export const sendCCAtMsImpl = (out, channel, controller, value, atMs) => {
  out.send([0xb0 | (channel & 0x0f), controller & 0x7f, value & 0x7f], atMs);
};

export const noteOnAtMsImpl = (out, channel, note, velocity, atMs) => {
  out.send([0x90 | (channel & 0x0f), note & 0x7f, velocity & 0x7f], atMs);
};

export const noteOffAtMsImpl = (out, channel, note, atMs) => {
  out.send([0x80 | (channel & 0x0f), note & 0x7f, 0], atMs);
};
