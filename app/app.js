// Week 1 skeleton: onboarding -> consent -> age gate -> spiral capture -> replay.
// Trace shape matches schema/trace.schema.json — keep both in sync.

const TURNS = 4;
const STORAGE_KEY = "neurotrace:lastTrace";
const REDUCED_MOTION = matchMedia("(prefers-reduced-motion: reduce)").matches;

function cssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

function strokeGradient(ctx, w, h) {
  const g = ctx.createLinearGradient(0, 0, w, h);
  g.addColorStop(0, cssVar("--accent"));
  g.addColorStop(1, cssVar("--warm"));
  return g;
}

// devicePixelRatio-aware canvas: backing store at full device resolution,
// context scaled so every other coordinate in this file stays in CSS pixels.
// The canvases live inside screens that start `hidden` (display:none), which
// has no layout box, so this can't run once at load — call it again right
// before a screen holding a canvas is revealed. setTransform (not scale)
// keeps repeat calls idempotent instead of compounding.
function fitCanvasToDisplay(canvas) {
  const dpr = window.devicePixelRatio || 1;
  const { width, height } = canvas.getBoundingClientRect();
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  canvas.getContext("2d").setTransform(dpr, 0, 0, dpr, 0, 0);
  return { width, height };
}

// ---------- spiral math, shared by the brand mark (SVG) and the capture guide (canvas) ----------

function spiralPoints(r0, r1, turns, steps) {
  const pts = [];
  for (let i = 0; i <= steps; i++) {
    const p = i / steps;
    const theta = p * turns * 2 * Math.PI;
    const r = r0 + p * (r1 - r0);
    pts.push([r * Math.cos(theta), r * Math.sin(theta)]);
  }
  return pts;
}

// ---------- brand mark: draw the actual spiral shape once on load ----------

function initBrandMark() {
  const path = document.getElementById("brand-spiral");
  if (!path) return;
  const cx = 17, cy = 17;
  const d = spiralPoints(3, 15, 2.2, 60)
    .map(([x, y], i) => (i === 0 ? "M" : "L") + (cx + x).toFixed(2) + "," + (cy + y).toFixed(2))
    .join(" ");
  path.setAttribute("d", d);

  const len = path.getTotalLength();
  path.style.strokeDasharray = len;
  if (REDUCED_MOTION) return; // fully drawn, no animation
  path.style.strokeDashoffset = len;
  requestAnimationFrame(() => {
    path.style.transition = "stroke-dashoffset 1100ms cubic-bezier(0.22,1,0.36,1) 120ms";
    path.style.strokeDashoffset = 0;
  });
}

// ---------- routing ----------

const STEP_ORDER = ["screen-onboarding", "screen-consent", "screen-agegate", "screen-capture", "screen-replay"];

function updateSteps(id) {
  const activeIndex = STEP_ORDER.indexOf(id);
  const dots = document.querySelectorAll("#steps span");
  dots.forEach((dot, i) => dot.classList.toggle("done", i <= activeIndex));
  document.getElementById("steps").setAttribute("aria-valuenow", activeIndex + 1);
}

function showScreen(id) {
  document.querySelectorAll(".screen").forEach((s) => (s.hidden = s.id !== id));
  updateSteps(id);
  if (id === "screen-capture") {
    ({ width: captureW, height: captureH } = fitCanvasToDisplay(captureCanvas));
    resetCapture(); // (re)draw the guide now that the canvas has a real size
  }
  if (id === "screen-replay") {
    ({ width: replayW, height: replayH } = fitCanvasToDisplay(replayCanvas));
    ({ width: speedW, height: speedH } = fitCanvasToDisplay(speedCanvas));
    startReplay(!REDUCED_MOTION); // auto-play on arrival: motion only if they didn't opt out
  }
}

document.querySelectorAll("[data-next]").forEach((btn) => {
  btn.addEventListener("click", () => {
    if (btn.disabled) return;
    showScreen(btn.dataset.next);
  });
});

document.querySelectorAll("[data-back]").forEach((btn) => {
  btn.addEventListener("click", () => showScreen(btn.dataset.back));
});

function wireCheckToggle(checkboxId, buttonId) {
  const checkbox = document.getElementById(checkboxId);
  const button = document.getElementById(buttonId);
  checkbox.addEventListener("change", () => {
    button.disabled = !checkbox.checked;
  });
}
wireCheckToggle("consent-check", "consent-continue");
wireCheckToggle("agegate-check", "agegate-continue");

// ---------- spiral guide ----------

function drawSpiralGuide(ctx, w, h) {
  const cx = w / 2;
  const cy = h / 2;
  const maxR = Math.min(w, h) / 2 - 20;
  ctx.save();
  ctx.strokeStyle = `color-mix(in srgb, ${cssVar("--ink")} 22%, transparent)`;
  ctx.lineWidth = 2;
  ctx.beginPath();
  spiralPoints(0, maxR, TURNS, 1000).forEach(([x, y], i) => {
    if (i === 0) ctx.moveTo(cx + x, cy + y);
    else ctx.lineTo(cx + x, cy + y);
  });
  ctx.stroke();
  ctx.restore();
}

// ---------- capture ----------

const captureCanvas = document.getElementById("capture-canvas");
const captureCtx = captureCanvas.getContext("2d");
let captureW = 0, captureH = 0; // real values set by fitCanvasToDisplay when screen-capture is shown
const replayBtn = document.getElementById("replay-btn");
const clearBtn = document.getElementById("clear-btn");

let samples = [];
let strokeStartTime = null;
let capturing = false;

function canvasPoint(canvas, clientX, clientY) {
  const rect = canvas.getBoundingClientRect();
  return { x: clientX - rect.left, y: clientY - rect.top };
}

function mapInputType(pointerType) {
  return pointerType === "pen" ? "pencil" : pointerType; // matches schema enum
}

const savedBadge = document.getElementById("saved-badge");
let savedBadgeTimer = null;

function flashSavedBadge() {
  clearTimeout(savedBadgeTimer);
  savedBadge.classList.add("show");
  savedBadgeTimer = setTimeout(() => savedBadge.classList.remove("show"), 2200);
}

function resetCapture() {
  captureCtx.clearRect(0, 0, captureW, captureH);
  drawSpiralGuide(captureCtx, captureW, captureH);
  samples = [];
  replayBtn.disabled = true;
  savedBadge.classList.remove("show");
}

function addSample(ev) {
  const p = canvasPoint(captureCanvas, ev.clientX, ev.clientY);
  const sample = {
    t: (ev.timeStamp - strokeStartTime) / 1000,
    x: p.x,
    y: p.y,
    pressure: ev.pressure || 0,
    tiltX: ev.tiltX || 0,
    tiltY: ev.tiltY || 0,
  };
  samples.push(sample);
  return sample;
}

captureCanvas.addEventListener("pointerdown", (ev) => {
  resetCapture(); // starting a new stroke discards any earlier one, on screen and in samples
  captureCanvas.setPointerCapture(ev.pointerId);
  capturing = true;
  strokeStartTime = ev.timeStamp;
  const s = addSample(ev);
  captureCtx.beginPath();
  captureCtx.moveTo(s.x, s.y);
  captureCtx.strokeStyle = strokeGradient(captureCtx, captureW, captureH);
  captureCtx.lineWidth = 3;
  captureCtx.lineCap = "round";
});

captureCanvas.addEventListener("pointermove", (ev) => {
  if (!capturing) return;
  // Chrome hands back the full sub-frame history; some browsers hand back an
  // empty list, which would drop every move sample and leave Replay disabled.
  const batch = ev.getCoalescedEvents ? ev.getCoalescedEvents() : [];
  for (const coalesced of batch.length ? batch : [ev]) {
    const s = addSample(coalesced);
    captureCtx.lineTo(s.x, s.y);
  }
  captureCtx.stroke();
});

function endCapture(ev) {
  if (!capturing) return;
  capturing = false;
  if (samples.length >= 2 && saveTrace(mapInputType(ev.pointerType))) {
    replayBtn.disabled = false;
    flashSavedBadge();
  }
}
captureCanvas.addEventListener("pointerup", endCapture);
captureCanvas.addEventListener("pointercancel", endCapture);

clearBtn.addEventListener("click", resetCapture);

// ---------- save (schema/trace.schema.json) ----------

function saveTrace(inputType) {
  const trace = {
    task: "spiral",
    hand: "right", // no hand-select UI yet — week 2 adds per-hand tasks
    inputType,
    deviceLabel: navigator.platform || "unknown", // a coarse hint, not the fingerprint-y full UA string
    samples,
  };
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(trace));
    return true;
  } catch (err) {
    console.warn("NeuroTrace: couldn't save trace (storage full or unavailable)", err);
    return false;
  }
}

function loadTrace() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (err) {
    console.warn("NeuroTrace: couldn't read saved trace", err);
    return null;
  }
}

// ---------- replay ----------

const replayCanvas = document.getElementById("replay-canvas");
const replayCtx = replayCanvas.getContext("2d");
let replayW = 0, replayH = 0;
const speedCanvas = document.getElementById("speed-canvas");
const speedCtx = speedCanvas.getContext("2d");
let speedW = 0, speedH = 0;
let replayFrame = null;
const replayAgainBtn = document.getElementById("replay-again-btn");

function drawSpeedGraph(trace) {
  const w = speedW;
  const h = speedH;
  speedCtx.clearRect(0, 0, w, h);
  const pts = trace.samples;
  if (pts.length < 2) return;

  const speeds = [];
  for (let i = 1; i < pts.length; i++) {
    const dt = pts[i].t - pts[i - 1].t;
    const dx = pts[i].x - pts[i - 1].x;
    const dy = pts[i].y - pts[i - 1].y;
    speeds.push(dt > 0 ? Math.hypot(dx, dy) / dt : 0);
  }
  if (speeds.length < 2) return; // one segment isn't a graph — avoid a /0 below
  const maxSpeed = Math.max(...speeds, 1);
  const coords = speeds.map((s, i) => [(i / (speeds.length - 1)) * w, h - (s / maxSpeed) * h]);

  const fill = speedCtx.createLinearGradient(0, 0, 0, h);
  fill.addColorStop(0, cssVar("--accent-soft"));
  fill.addColorStop(1, "transparent");
  speedCtx.fillStyle = fill;
  speedCtx.beginPath();
  speedCtx.moveTo(coords[0][0], h);
  coords.forEach(([x, y]) => speedCtx.lineTo(x, y));
  speedCtx.lineTo(coords[coords.length - 1][0], h);
  speedCtx.closePath();
  speedCtx.fill();

  speedCtx.strokeStyle = cssVar("--accent");
  speedCtx.lineWidth = 2;
  speedCtx.beginPath();
  coords.forEach(([x, y], i) => (i === 0 ? speedCtx.moveTo(x, y) : speedCtx.lineTo(x, y)));
  speedCtx.stroke();
}

// `animate` is the user explicitly asking to watch the stroke redraw (Play
// again). Landing on the screen replays by itself, so that one honours
// prefers-reduced-motion and paints the finished trace in a single frame.
function playReplay(trace, animate) {
  cancelAnimationFrame(replayFrame); // don't leave an older loop drawing over this one
  replayCtx.clearRect(0, 0, replayW, replayH);
  drawSpiralGuide(replayCtx, replayW, replayH);
  const pts = trace.samples;
  if (!pts.length) return;

  replayCtx.strokeStyle = strokeGradient(replayCtx, replayW, replayH);
  replayCtx.lineWidth = 3;
  replayCtx.lineCap = "round";

  function drawSegment(i) {
    replayCtx.beginPath();
    replayCtx.moveTo(pts[i - 1].x, pts[i - 1].y);
    replayCtx.lineTo(pts[i].x, pts[i].y);
    replayCtx.stroke();
  }

  if (!animate) {
    for (let i = 1; i < pts.length; i++) drawSegment(i);
    return;
  }

  const start = performance.now();
  let i = 1;
  function step(now) {
    const elapsed = (now - start) / 1000;
    while (i < pts.length && pts[i].t <= elapsed) {
      drawSegment(i);
      i++;
    }
    if (i < pts.length) replayFrame = requestAnimationFrame(step);
  }
  replayFrame = requestAnimationFrame(step);
}

function startReplay(animate) {
  const trace = loadTrace();
  if (!trace || !trace.samples || trace.samples.length < 2) {
    // silent return here is what makes a dead Play again button impossible to debug
    console.warn("NeuroTrace: no replayable trace saved — capture a spiral first");
    return;
  }
  drawSpeedGraph(trace);
  playReplay(trace, animate);
}
replayAgainBtn.addEventListener("click", () => startReplay(true));

// ---------- init ----------
// (capture/replay canvases are sized lazily in showScreen — they start
// inside `hidden` screens, which have no layout box to measure yet)

initBrandMark();
