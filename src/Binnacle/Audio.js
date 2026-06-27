let ctx = null;
let armed = false;

// Create (once) and resume the keep-alive context: one oscillator at an
// inaudible level (-80 dB), permanently connected to the output, so the tab
// registers as "playing audio" — exempting it from background timer throttling
// and macOS App Nap. Safe to call repeatedly (resumes if the context was
// suspended by an OS sleep/wake).
const ensure = () => {
  try {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    if (!ctx) {
      ctx = new AC();
      const osc = ctx.createOscillator();
      const g = ctx.createGain();
      g.gain.value = 0.0001; // inaudible, but a real (non-zero) signal = audio activity
      osc.connect(g);
      g.connect(ctx.destination);
      osc.start();
    }
    if (ctx.state === "suspended") ctx.resume();
  } catch (e) {
    /* no Web Audio available — nothing we can do, fall back to worker-only */
  }
};

export const armAudioKeepAlive = () => {
  if (armed) return;
  armed = true;
  // First gesture creates+resumes; later gestures re-resume after any OS suspend.
  window.addEventListener("pointerdown", ensure);
  window.addEventListener("keydown", ensure);
};
