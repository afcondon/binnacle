"use strict";

export const openImpl = (url, handlers) => {
  const ws = new WebSocket(url);
  ws.onopen = () => handlers.onOpen();
  // handlers.onMessage is an EffectFn1 — calling it runs the effect.
  ws.onmessage = (ev) => handlers.onMessage(ev.data);
  ws.onclose = () => handlers.onClose();
  return ws;
};

export const sendImpl = (ws, msg) => {
  if (ws.readyState === 1 /* WebSocket.OPEN */) ws.send(msg);
};
