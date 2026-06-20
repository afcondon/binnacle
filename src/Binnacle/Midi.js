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
