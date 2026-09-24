// onboarding -> consent -> age gate -> spiral capture -> replay -> results.
// Trace shape matches schema/trace.schema.json — keep both in sync.

import {
  SPIRAL_FEATURE_ORDER,
  featuresFromTrace,
  preprocessTrace,
  normalize,
} from "./nt-features.js";

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

const STEP_ORDER = [
  "screen-onboarding", "screen-consent", "screen-agegate",
  "screen-capture", "screen-replay", "screen-results",
];

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
  if (id === "screen-results") {
    ({ width: overlayW, height: overlayH } = fitCanvasToDisplay(overlayCanvas));
    renderResults();
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

// ---------- scoring ----------
// Everything in this section answers to Markdowns/NeuroTrace_ClaimsRules.md.
// The model emits a probability; the probability never reaches the DOM. What
// the user sees is where they sit against a reference sample, which is the
// honest equivalent and is more informative anyway.

// Percentile of the score against the reference distribution. Provisional —
// Sanchit confirms these against ClaimsRules before this ships to anyone.
const RESULT_TIERS = [
  { max: 0.75, label: "Within typical range" },
  { max: 0.95, label: "Some measures outside typical range" },
  { max: 1.01, label: "Multiple measures outside typical range" },
];

// Plain language for every key in SPIRAL_FEATURE_ORDER. Lower case and
// sentence-fragment shaped on purpose — they get slotted into a sentence.
const MEASURE_PHRASE = {
  spiral_duration: "how long the drawing took",
  spiral_max_deviation: "the largest wobble off your own best-fit spiral",
  spiral_mean_deviation: "the average wobble off your own best-fit spiral",
  spiral_std_deviation: "how much that wobble varied",
  spiral_major_reversals: "how often the pen pulled back and corrected course",
  spiral_mean_speed: "your average drawing speed",
  spiral_std_speed: "how much your speed varied",
  spiral_ldlj: "how smooth the motion was",
  spiral_sparc: "how smooth the motion was, measured a second way",
  spiral_tremor_4_6: "your 4–6 Hz tremor power",
  spiral_tremor_6_12: "your 6–12 Hz tremor power",
  spiral_tremor_dominant_hz: "your dominant wobble frequency",
};

const NOT_A_DIAGNOSIS =
  "These are measurements of how you moved during the tasks, compared with other people who " +
  "took the same tasks. They are not a diagnosis and cannot tell you whether you have a " +
  "neurological condition.";
const MANY_THINGS =
  "Many things move these numbers — caffeine, fatigue, sleep, anxiety, medication timing, cold " +
  "hands, familiarity with the task. One drawing is a single reading, not a pattern.";

// Indexed by tier, same order as RESULT_TIERS.
const TIER_COPY = [
  [NOT_A_DIAGNOSIS,
   "Draw the spiral again on another day if you want to see how much your own numbers move " +
   "between sittings. Your own baseline is the comparison that means the most over time."],
  [NOT_A_DIAGNOSIS, MANY_THINGS,
   "Draw the spiral again over the next few days. A measure that keeps landing outside the " +
   "typical range tells you more than one that did it once."],
  [NOT_A_DIAGNOSIS, MANY_THINGS,
   "If you have already noticed a change in how you move, these measurements are something " +
   "concrete to bring to a doctor. There is no disease-modifying therapy for Parkinson's today, " +
   "so this is not about urgency — earlier conversations mean earlier symptom management and " +
   "earlier access to clinical trials."],
];

// Both files sit next to index.html. Loaded once, eagerly, so a mismatched or
// missing model surfaces the moment anyone asks for results. The bare .catch
// only marks the rejection as handled; renderResults still awaits and reports it.
const modelPromise = loadModel();
modelPromise.catch(() => {});

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`couldn't load ${url} (HTTP ${res.status})`);
  return res.json();
}

async function loadModel() {
  const [model, percentiles] = await Promise.all([
    fetchJson("model.json"),
    fetchJson("percentiles.json"),
  ]);

  // A featureOrder mismatch means the model is being handed numbers it was
  // never trained on, in positions that no longer mean what its weights think.
  // There is no safe way to score through that, so stop here and say so.
  const expected = SPIRAL_FEATURE_ORDER.join(",");
  if (!Array.isArray(model.featureOrder) || model.featureOrder.join(",") !== expected) {
    throw new Error(
      "model.json was exported for a different set of features than this app computes. " +
      `It expects [${model.featureOrder}] and this build produces [${SPIRAL_FEATURE_ORDER}]. ` +
      "Re-export the model from training/scripts/export_model.py.");
  }
  for (const k of ["mean", "scale", "weights"]) {
    if (!Array.isArray(model[k]) || model[k].length !== model.featureOrder.length) {
      throw new Error(`model.json: ${k} must have one entry per feature.`);
    }
  }
  const missing = SPIRAL_FEATURE_ORDER.filter((k) => !Array.isArray(percentiles.features?.[k]));
  if (missing.length || !Array.isArray(percentiles.score)) {
    throw new Error(`percentiles.json is missing reference values for: ${missing.join(", ") || "score"}.`);
  }
  return { model, percentiles };
}

function score(features, model) {
  let z = model.bias;
  for (let i = 0; i < model.featureOrder.length; i++) {
    const raw = features[model.featureOrder[i]];
    const standardized = (raw - model.mean[i]) / model.scale[i];
    z += model.weights[i] * standardized;
  }
  return 1 / (1 + Math.exp(-z));   // 0..1 — internal only, NEVER shown
}

// spiral_sparc comes back NaN on a trace too short to have a usable spectrum.
// Substituting the training mean makes that feature contribute nothing rather
// than poisoning z; the row is dropped from the display either way.
function scoringFeatures(features, model) {
  const out = {};
  model.featureOrder.forEach((k, i) => {
    out[k] = Number.isFinite(features[k]) ? features[k] : model.mean[i];
  });
  return out;
}

// Fraction of the reference sample strictly below v. `sorted` is ascending;
// n is ~15-50 so a scan beats the binary search it would take to explain.
function percentile(v, sorted) {
  let below = 0;
  for (const ref of sorted) if (ref < v) below++;
  return below / sorted.length;
}

const tierIndexFor = (p) => RESULT_TIERS.findIndex((t) => p < t.max);

// ---------- results screen ----------

const overlayCanvas = document.getElementById("overlay-canvas");
const overlayCtx = overlayCanvas.getContext("2d");
let overlayW = 0, overlayH = 0;
const resultsBody = document.getElementById("results-body");
const resultsError = document.getElementById("results-error");

function showResultsError(message) {
  resultsBody.hidden = true;
  resultsError.hidden = false;
  resultsError.innerHTML =
    `<h1>We can't show results</h1><p>${message}</p>` +
    `<p>Nothing was scored. Your drawing is still saved — go back and try replaying it.</p>`;
}

const sentenceCase = (str) => str.charAt(0).toUpperCase() + str.slice(1);

// One row: the sentence is the row. The dot is a second reading of the same
// number for people who scan rather than read, which is why it is aria-hidden.
function measureRow(key, pct) {
  const p = Math.round(pct * 100);
  const higher = p >= 50;
  const sentence =
    `${sentenceCase(MEASURE_PHRASE[key])} is ${higher ? "higher" : "lower"} than ` +
    `${higher ? p : 100 - p}% of our reference sample.`;
  return `<li class="measure">
      <p class="measure-text">${sentence}</p>
      <div class="measure-track" aria-hidden="true"><span class="measure-dot" style="--p:${p}%"></span></div>
    </li>`;
}

async function renderResults() {
  resultsError.hidden = true;
  resultsBody.hidden = false;

  const trace = loadTrace();
  if (!trace || !trace.samples || trace.samples.length < 2) {
    showResultsError("There's no saved spiral to measure yet.");
    return;
  }

  let model, percentiles, features;
  try {
    ({ model, percentiles } = await modelPromise);
  } catch (err) {
    console.error("NeuroTrace: model failed to load", err);
    showResultsError(err.message);
    return;
  }

  try {
    features = featuresFromTrace(trace);
  } catch (err) {
    // Short traces, spirals under one turn — real conditions, not bugs.
    console.warn("NeuroTrace: couldn't extract features", err);
    showResultsError(`We couldn't measure that drawing: ${err.message}. Draw the full spiral from the centre outwards and try again.`);
    return;
  }

  const scored = scoringFeatures(features, model);
  const prob = score(scored, model);           // stays in this scope and in IndexedDB
  const tierIndex = Math.max(0, tierIndexFor(percentile(prob, percentiles.score)));
  const tier = RESULT_TIERS[tierIndex];

  const tierEl = document.getElementById("results-tier");
  tierEl.textContent = tier.label;
  tierEl.dataset.tier = tierIndex;

  const { nHealthy, sources } = model.trainedOn;
  document.getElementById("results-reference").textContent =
    `Compared with ${nHealthy} healthy adults recorded in ${sources.join(", ")}.`;

  // |weight × standardized| is how much each feature actually pushed z, which
  // is a different question from which weight is biggest.
  const contributions = model.featureOrder
    .map((key, i) => ({
      key,
      push: Math.abs(model.weights[i] * ((scored[key] - model.mean[i]) / model.scale[i])),
    }))
    .sort((a, b) => b.push - a.push)
    .slice(0, 3);
  document.getElementById("results-top").innerHTML = contributions
    .map(({ key }) => `<li>${sentenceCase(MEASURE_PHRASE[key])}</li>`)
    .join("");

  // A NaN feature gets no row rather than a row reading "NaN".
  document.getElementById("results-measures").innerHTML = SPIRAL_FEATURE_ORDER
    .filter((key) => Number.isFinite(features[key]))
    .map((key) => measureRow(key, percentile(features[key], percentiles.features[key])))
    .join("");

  document.getElementById("results-meaning").innerHTML =
    TIER_COPY[tierIndex].map((para) => `<p>${para}</p>`).join("");

  drawOverlay(trace);
  saveAssessment({
    ts: Date.now(),
    task: trace.task,
    inputType: trace.inputType,
    traceKey: traceKey(trace),
    features,
    prob,
    tier: tier.label,
    samples: trace.samples,
  }).catch((err) => console.warn("NeuroTrace: couldn't save this assessment", err));
}

// ---------- raw vs filtered overlay ----------

// Both paths go through normalize() — the same centre-and-scale preprocessTrace
// applies — so they land in one coordinate space and the only visible
// difference between them is the trimming, resampling and low-pass.
function drawOverlay(trace) {
  overlayCtx.clearRect(0, 0, overlayW, overlayH);
  const t = Float64Array.from(trace.samples, (s) => s.t);
  const x = Float64Array.from(trace.samples, (s) => s.x);
  const y = Float64Array.from(trace.samples, (s) => s.y);

  let raw, filtered;
  try {
    raw = normalize(x, y);
    filtered = preprocessTrace(t, x, y).slice(1);
  } catch (err) {
    console.warn("NeuroTrace: couldn't draw the overlay", err);
    return;
  }

  const fit = fitPaths([raw, filtered], overlayW, overlayH, 24);
  strokePath(overlayCtx, raw, fit, cssVar("--ink-soft"), 2);
  strokePath(overlayCtx, filtered, fit, strokeGradient(overlayCtx, overlayW, overlayH), 3);
}

function fitPaths(paths, w, h, pad) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const [px, py] of paths) {
    for (let i = 0; i < px.length; i++) {
      if (px[i] < minX) minX = px[i];
      if (px[i] > maxX) maxX = px[i];
      if (py[i] < minY) minY = py[i];
      if (py[i] > maxY) maxY = py[i];
    }
  }
  const s = Math.min((w - 2 * pad) / (maxX - minX || 1), (h - 2 * pad) / (maxY - minY || 1));
  return { s, ox: w / 2 - s * (minX + maxX) / 2, oy: h / 2 - s * (minY + maxY) / 2 };
}

function strokePath(ctx, [px, py], { s, ox, oy }, style, lineWidth) {
  ctx.save();
  ctx.strokeStyle = style;
  ctx.lineWidth = lineWidth;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.beginPath();
  for (let i = 0; i < px.length; i++) {
    const X = ox + s * px[i], Y = oy + s * py[i];
    if (i === 0) ctx.moveTo(X, Y); else ctx.lineTo(X, Y);
  }
  ctx.stroke();
  ctx.restore();
}

// ---------- history (IndexedDB) ----------
// Features + score are a few hundred bytes and are kept for good — they are
// the whole point of measuring over time. Raw samples are ~100 KB each, so
// only the newest RAW_KEEP assessments hold on to theirs.

const DB_NAME = "neurotrace";
const DB_STORE = "assessments";
const RAW_KEEP = 3;

// Enough to tell one drawing from another. Two traces colliding here would
// have to share a sample count, a duration and an end point.
// ponytail: fingerprint, not a hash — swap in a real digest if traces ever
// arrive from somewhere other than this device's own capture screen.
const traceKey = ({ samples }) => {
  const last = samples[samples.length - 1];
  return `${samples.length}:${last.t.toFixed(3)}:${last.x.toFixed(2)}:${last.y.toFixed(2)}`;
};

const request = (req) => new Promise((resolve, reject) => {
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});

function openDb() {
  const req = indexedDB.open(DB_NAME, 1);
  req.onupgradeneeded = () => req.result.createObjectStore(DB_STORE, { keyPath: "id", autoIncrement: true });
  return request(req);
}

const txDone = (tx) => new Promise((resolve, reject) => {
  tx.oncomplete = () => resolve();
  tx.onerror = tx.onabort = () => reject(tx.error);
});

async function saveAssessment(record) {
  const db = await openDb();
  try {
    // Looking at the same result twice is one assessment, not two — otherwise
    // "how has this changed over time" fills up with re-reads of one drawing.
    const newest = await request(
      db.transaction(DB_STORE, "readonly").objectStore(DB_STORE).openCursor(null, "prev"));
    if (newest && newest.value.traceKey === record.traceKey) return;

    const tx = db.transaction(DB_STORE, "readwrite");
    const store = tx.objectStore(DB_STORE);
    store.add(record);
    // Same transaction, so the cursor already sees the record just added.
    let seen = 0;
    store.openCursor(null, "prev").onsuccess = (ev) => {
      const cur = ev.target.result;
      if (!cur) return;
      if (++seen > RAW_KEEP && cur.value.samples) {
        const { samples, ...rest } = cur.value;
        cur.update(rest);
      }
      cur.continue();
    };
    await txDone(tx);
  } finally {
    db.close();
  }
}

async function listAssessments() {
  const db = await openDb();
  try {
    const tx = db.transaction(DB_STORE, "readonly");
    const all = request(tx.objectStore(DB_STORE).getAll());
    await txDone(tx);
    return all;
  } finally {
    db.close();
  }
}

// No history screen yet — this is the read side, so past records are reachable
// from the console and from whatever renders them next.
window.neurotrace = { listAssessments };

// ---------- init ----------
// (capture/replay canvases are sized lazily in showScreen — they start
// inside `hidden` screens, which have no layout box to measure yet)

initBrandMark();
