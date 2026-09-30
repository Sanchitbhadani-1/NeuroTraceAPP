// the drawing pad: spiral guide, start dot, and pointer capture into the
// trace shape of schema/trace.schema.json. holds no app state - the personal
// #draw flow and collection mode each wrap their own canvas with it.
//
// the canvas has to sit alone in a positioned sheet (<div class="pad">) bc the
// pad puts the start dot's pulsing halo in there, under the transparent
// canvas.

const TURNS = 4;

// shared by the pad guide and app.js's brand mark and spiral art.
export function spiralPoints(r0, r1, turns, steps) {
  const pts = [];
  for (let i = 0; i <= steps; i++) {
    const p = i / steps;
    const theta = p * turns * 2 * Math.PI;
    const r = r0 + p * (r1 - r0);
    pts.push([r * Math.cos(theta), r * Math.sin(theta)]);
  }
  return pts;
}

const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

// matches the schema's inputType enum.
const mapInputType = (pointerType) => (pointerType === "pen" ? "pencil" : pointerType);

// a coarse hint, not the fingerprint-y full UA string. iPadOS Safari
// reports itself as a Mac by default, but no Mac has a multi-touch screen.
function deviceLabel() {
  if (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) return "iPad";
  return navigator.userAgent.match(/iPhone|iPad/)?.[0] ?? (navigator.platform || "unknown");
}

// onInk(info) runs when the trial's ink changes without the caller asking:
// at every stroke start ({}) and when a resize wipes it ({ cleared: "resize" }).
export function createPad(canvas, { onInk }) {
  const ctx = canvas.getContext("2d");
  const halo = document.createElement("span");
  halo.className = "pad-start";
  halo.hidden = true;
  canvas.before(halo); // earlier in the sheet = painted under the canvas

  let w = 0, h = 0;          // CSS size of the canvas - every coordinate is in this space
  let samples = [];          // the whole trial - never reset by a pointerdown (Constraint 5)
  let starts = [];           // index into samples where each stroke begins
  let t0 = 0;                // timeStamp of the trial's first sample
  let inputType = null;      // from the trial's first pointer
  let penSeen = false;
  let active = null;         // pointerId of the stroke in progress
  let dot = false;

  function draw() {
    if (!w) return; // not laid out yet (screen hidden), the ResizeObserver draws it when it shows
    ctx.clearRect(0, 0, w, h);

    ctx.strokeStyle = cssVar("--guide");
    ctx.lineWidth = Math.max(2, w / 180);
    ctx.beginPath();
    const maxR = Math.min(w, h) / 2 - 20;
    for (const [x, y] of spiralPoints(0, maxR, TURNS, 1000)) ctx.lineTo(w / 2 + x, h / 2 + y);
    ctx.stroke();

    if (dot) {
      ctx.fillStyle = cssVar("--accent");
      ctx.beginPath();
      ctx.arc(w / 2, h / 2, 7.5, 0, 2 * Math.PI);
      ctx.fill();
    }

    starts.forEach((start, i) => ink(start, starts[i + 1] ?? samples.length));
  }

  // strokes samples[from - 1 .. to) - or, for a stroke's first sample, a
  // zero-length line, which the round caps turn into a dot so a tap still shows.
  function ink(from, to) {
    const first = starts.includes(from) ? from : from - 1;
    ctx.strokeStyle = cssVar("--accent");
    ctx.lineWidth = Math.max(3, w / 110);
    ctx.lineCap = ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(samples[first].x, samples[first].y);
    for (let i = first; i < to; i++) ctx.lineTo(samples[i].x, samples[i].y);
    ctx.stroke();
  }

  // devicePixelRatio-aware: backing store at full device resolution, context
  // scaled so everything else stays in CSS pixels. setTransform (not scale)
  // keeps repeat calls idempotent so they don't compound.
  new ResizeObserver(([entry]) => {
    const { width, height } = entry.contentRect;
    if (!width || !height) return; // hidden screen: keep the trial for when it comes back
    // a sample only means something against the canvas size it was drawn on,
    // so a trial can't straddle a resize (rotation, split view).
    const cleared = (width !== w || height !== h) && samples.length > 0;
    if (cleared) reset();
    w = width;
    h = height;
    const dpr = devicePixelRatio || 1;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
    if (cleared) onInk({ cleared: "resize" });
  }).observe(canvas);

  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", draw);

  // read at event time, never cached - screens slide in (a 280 ms translateY)
  // and a rect taken mid-slide would offset every y against the guide.
  function addSamples(events) {
    const rect = canvas.getBoundingClientRect();
    const from = samples.length;
    for (const ev of events) {
      if (!samples.length) t0 = ev.timeStamp;
      samples.push({
        t: (ev.timeStamp - t0) / 1000,
        x: ev.clientX - rect.left,
        y: ev.clientY - rect.top,
        pressure: ev.pressure || 0,
        tiltX: ev.tiltX || 0,
        tiltY: ev.tiltY || 0,
      });
    }
    ink(from, samples.length);
  }

  canvas.addEventListener("pointerdown", (ev) => {
    if (ev.pointerType === "pen") {
      // a palm that landed before the Pencil isn't part of the drawing:
      // while the trial is still touch-only the first pen drops that ink
      // (and the touch pointer, even mid-stroke) and starts the trial fresh.
      // Constraint 5 still holds for the drawer's own pen lifts.
      // ponytail: a finger-then-Pencil switch mid-trial loses the finger ink,
      // keep it only if people really do switch.
      if (!penSeen && inputType === "touch") reset();
      penSeen = true;
    }
    if (!ev.isPrimary || ev.button !== 0 || active !== null) return; // one pointer at a time
    if (ev.pointerType === "touch" && penSeen) return; // palm resting beside the pencil
    active = ev.pointerId;
    if (dot) showStartDot(false);
    if (!samples.length) inputType = mapInputType(ev.pointerType);
    // a lifted finger carries on in the same trial: same samples, same t0,
    // just a gap in t - never a reset.
    starts.push(samples.length);
    addSamples([ev]);
    onInk({});
    // last on purpose: it throws for a pointerId the browser doesn't know (synthetic
    // events), and by then the stroke state is already consistent.
    canvas.setPointerCapture(ev.pointerId);
  });

  canvas.addEventListener("pointermove", (ev) => {
    if (ev.pointerId !== active) return;
    // Chrome hands back the full sub-frame history but some browsers hand back
    // an empty list, which would drop every move sample.
    const batch = ev.getCoalescedEvents ? ev.getCoalescedEvents() : [];
    addSamples(batch.length ? batch : [ev]);
  });

  const end = (ev) => { if (ev.pointerId === active) active = null; };
  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", end);

  function reset() {
    samples = [];
    starts = [];
    inputType = null;
    penSeen = false;
    active = null;
    draw();
  }

  function showStartDot(on) {
    dot = on;
    halo.hidden = !on;
    draw();
  }

  return {
    reset,
    showStartDot,
    hasInk: () => samples.length > 0,
    // copies: the pad stays live and a kept trial can't grow after its
    // features were computed.
    strokeStarts: () => starts.slice(),
    trace: (hand) => ({ task: "spiral", hand, inputType, deviceLabel: deviceLabel(), samples: samples.slice() }),
  };
}
