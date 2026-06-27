// The worker's whole job: a bare metronome. It owns nothing but a setInterval
// that posts an empty tick, and clears it on a stop message. Kept as an inline
// blob so there is no separate worker file to serve alongside the single
// app bundle (matters for static deploys).
const workerSrc =
  "let id = null;\n" +
  "onmessage = function (e) {\n" +
  "  if (e.data && e.data.stop) { if (id !== null) { clearInterval(id); id = null; } }\n" +
  "  else { id = setInterval(function () { postMessage(0); }, e.data.tickMs); }\n" +
  "};";

// onTick is a PureScript `Effect Unit` (a `() => ...` thunk); the returned
// canceller is likewise an `Effect Unit`.
export const startWorkerTicker = (tickMs) => (onTick) => () => {
  // Correct-but-throttled fallback for environments without Worker/Blob/URL.
  const fallback = () => {
    const h = setInterval(onTick, tickMs);
    return () => clearInterval(h);
  };
  try {
    if (
      typeof Worker === "undefined" ||
      typeof Blob === "undefined" ||
      typeof URL === "undefined" ||
      !URL.createObjectURL
    ) {
      return fallback();
    }
    const blob = new Blob([workerSrc], { type: "application/javascript" });
    const url = URL.createObjectURL(blob);
    const w = new Worker(url);
    w.onmessage = function () { onTick(); };
    w.postMessage({ tickMs: tickMs });
    return () => {
      try { w.postMessage({ stop: true }); } catch (_) { /* already gone */ }
      w.terminate();
      URL.revokeObjectURL(url);
    };
  } catch (_) {
    return fallback();
  }
};
