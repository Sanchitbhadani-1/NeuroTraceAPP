// App shell: a hash router over the <section class="screen"> elements in
// index.html, plus the setup screens (welcome -> consent -> about you, and
// home). Drawing, results and collection mode plug into the same router.
// Scoring lives in score.js, every sentence in copy.js, storage in store.js.

import { SPIRAL_FEATURE_ORDER, featuresFromTrace, normalize, preprocessTrace } from "./nt-features.js";
import { checkScoringFiles, scoreSession } from "./score.js";
import * as copy from "./copy.js";
import { getPrefs, setPrefs, saveAssessment, listAssessments, getAssessment, clearAssessments, saveCollected, listCollected, markExported, subjects, newSubjectId } from "./store.js";
import { createPad, spiralPoints } from "./pad.js";
import { reduced, applyMotion, swap, moveLens, reveal, countUp, watchTitle, toast, mountMascots, measuring } from "./motion.js";

// ---------- spiral art (the guide spiral itself is pad.js's spiralPoints) ----------

// A believable hand-drawn line for the welcome and home art: the guide spiral
// pushed in and out along its radius by a slow wobble plus a little jitter,
// faded in over the first fifth so it starts on the centre. Same recipe as
// the design canvas, so the art matches the mockups.
function handDrawn(r1, turns, steps) {
  return spiralPoints(0, r1, turns, steps).map(([x, y], i) => {
    const p = i / steps;
    const th = p * turns * 2 * Math.PI;
    const wobble = 4 * (0.6 * Math.sin(th * 0.45 + 1.3) + 0.3 * Math.sin(th * 1.3 + 2.73) + 0.1 * Math.sin(th * 3.7 + 0.91));
    const dr = (wobble + 0.4 * Math.sin(i * 2.39996)) * Math.min(1, p * 5);
    return [x + dr * Math.cos(th), y + dr * Math.sin(th)];
  });
}

// ---------- brand mark and spiral art: drawn once on load ----------
// Every piece of art is a 340 × 340 viewBox centred on (170, 170), the
// geometry the design canvas used; CSS sets stroke widths per place.

function drawArt() {
  const art = {
    mark: spiralPoints(0, 150, 2.25, 120),
    "art-guide": spiralPoints(0, 150, 4, 720),
    "art-trace": handDrawn(150, 4, 720),
  };
  for (const [cls, pts] of Object.entries(art)) {
    const d = pts.map(([x, y], i) => `${i ? "L" : "M"}${(170 + x).toFixed(1)} ${(170 + y).toFixed(1)}`).join("");
    document.querySelectorAll(`path.${cls}`).forEach((path) => path.setAttribute("d", d));
  }
}

// ---------- scoring files ----------
// Both files sit next to index.html. Loaded once, eagerly, so a mismatched or
// missing model surfaces the moment anyone needs scoring. A model handed
// numbers in positions its weights don't expect has no safe way to score, so
// the router sends every scoring path to the error screen instead
// (Global Constraint 4). Scoring code reads `const { model, reference } = await scoring`.

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`couldn't load ${url} (HTTP ${res.status})`);
  return res.json();
}

async function loadScoring() {
  const [model, reference] = await Promise.all([fetchJson("model.json"), fetchJson("reference.json")]);
  checkScoringFiles(model, reference, SPIRAL_FEATURE_ORDER);
  const unnamed = SPIRAL_FEATURE_ORDER.filter((k) => !copy.MEASURES[k]);
  if (unnamed.length) throw new Error(`copy.js MEASURES has no entry for: ${unnamed.join(", ")}.`);
  return { model, reference };
}

let loadError = null;
const scoring = loadScoring();
scoring.catch((err) => {
  loadError = err;
  console.error("NeuroTrace: scoring files failed to load - nothing will be scored", err);
});

// ---------- session state (this page load only) ----------

let choice = null;     // { ageChoice, bracket, hand } from About you - #draw needs it
let current = null;    // the result being shown - #results needs it
let collecting = null; // the collection session in progress - screens past #collect need it

// ---------- router ----------
// location.hash is "#<screen>[/<param>]", e.g. "#home" or "#results/12".

let previous = null; // the screen shown before this one

function resolve(name, param) {
  const prefs = getPrefs();
  const fallback = prefs.onboarded ? "home" : "welcome";
  if (!name || !document.getElementById(`screen-${name}`)) return fallback;
  if (name === "error") return loadError ? name : fallback;
  // Collection mode is run by a facilitator, not the person on the personal
  // consent flow, so it has its own gate.
  if (name.startsWith("collect")) return name === "collect" || collecting ? name : "collect";
  if (!prefs.consented && name !== "welcome" && name !== "consent") return "welcome";
  if (name === "draw" && !choice) return "about";
  if (name === "results" && !current && !param) return "home"; // #results/<id> loads from history
  return name;
}

async function route() {
  const hash = location.hash;
  const [name, param] = hash.slice(1).split("/");
  const target = resolve(name, param);
  if (target !== name) return location.replace(`#${target}`); // fires hashchange -> route again

  if (name === "draw" || name === "results") {
    try {
      await scoring;
    } catch {
      return location.replace("#error");
    }
    if (location.hash !== hash) return; // the user moved on while the files loaded
  }
  show(name, param);
}

// Per-screen setup, run each time the screen is shown.
const onShow = {};
const TABS = new Set(["home", "settings", "about-app"]);

const TAB_ORDER = ["home", "settings", "about-app"];
const TITLED = new Set([...TAB_ORDER, "results"]); // screens whose large title collapses on scroll

// Tabs slide towards the tab you picked; everything else rises into place.
function show(name, param) {
  const from = TAB_ORDER.indexOf(previous), to = TAB_ORDER.indexOf(name);
  const kind = from >= 0 && to >= 0 && from !== to ? (to > from ? "left" : "right") : "fade";
  swap(() => showNow(name, param), { kind });
}

function showNow(name, param) {
  for (const s of document.querySelectorAll(".screen")) s.hidden = s.id !== `screen-${name}`;
  const screen = document.getElementById(`screen-${name}`);
  document.title = `${screen.dataset.title} — NeuroTrace`;
  onShow[name]?.(param);
  scrollTo(0, 0);
  screen.querySelector("h1").focus({ preventScroll: true });
  // The tab bar belongs to the three tab screens only; a check-in or a
  // collection session is a focused task with its own Back/Cancel.
  const tabbar = document.getElementById("tabbar");
  tabbar.hidden = !TABS.has(name);
  for (const a of tabbar.querySelectorAll("a")) {
    if (a.dataset.tab === name) a.setAttribute("aria-current", "page");
    else a.removeAttribute("aria-current");
  }
  moveLens(tabbar);
  watchTitle(TITLED.has(name) ? screen.querySelector("h1") : null);
  previous = name;
}

// ---------- consent ----------

const consentBoxes = document.querySelectorAll('#screen-consent input[name="consent"]');
const consentContinue = document.getElementById("consent-continue");
const consentHelp = document.getElementById("consent-help");

function syncConsent() {
  const ready = [...consentBoxes].every((box) => box.checked);
  consentContinue.disabled = !ready;
  consentHelp.hidden = ready;
}

onShow.consent = () => {
  const { consented } = getPrefs();
  consentBoxes.forEach((box) => (box.checked = consented));
  syncConsent();
};
document.getElementById("screen-consent").addEventListener("change", syncConsent);
consentContinue.addEventListener("click", () => {
  setPrefs({ consented: true, onboarded: true });
  location.hash = "#about";
});

// ---------- about you ----------

const aboutContinue = document.getElementById("about-continue");
const checkedValue = (name) => document.querySelector(`#screen-about input[name="${name}"]:checked`)?.value;
const syncAbout = () => (aboutContinue.disabled = !(checkedValue("age") && checkedValue("hand")));

document.getElementById("age-choices").innerHTML = copy.AGE_CHOICES
  .map(({ label }) => `<label class="chip"><input type="radio" name="age" value="${label}"><span>${label}</span></label>`)
  .join("");

onShow.about = () => {
  const { ageChoice, hand } = getPrefs();
  document.querySelectorAll('#screen-about input[name="age"]').forEach((r) => (r.checked = r.value === ageChoice));
  document.querySelectorAll('#screen-about input[name="hand"]').forEach((r) => (r.checked = r.value === hand));
  syncAbout();
  // First run arrives from consent; a check-in started from home (or a
  // reload) should go back home, not through consent again.
  document.getElementById("about-back").href = previous === "consent" ? "#consent" : "#home";
};
document.getElementById("screen-about").addEventListener("change", syncAbout);
aboutContinue.addEventListener("click", () => {
  const ageChoice = checkedValue("age");
  const hand = checkedValue("hand");
  setPrefs({ ageChoice, hand });
  choice = { ageChoice, bracket: copy.AGE_CHOICES.find((c) => c.label === ageChoice).bracket, hand };
  location.hash = "#draw";
});

// ---------- draw ----------
// One check-in is three spirals, averaged (handoff §6: averaging three
// drawings cuts within-person noise). Collection mode also records three, so
// the device-matched reference will be built the same way.
const CHECKIN_TRIALS = 3;

const drawDone = document.getElementById("draw-done");
const drawStatus = document.getElementById("draw-status");
const drawSheet = document.getElementById("draw-pad").parentElement;
let trials = []; // this check-in's finished spirals: { trace, strokeStarts, features }
let trialsWanted = CHECKIN_TRIALS;

const pad = createPad(document.getElementById("draw-pad"), {
  onInk({ cleared }) {
    drawDone.disabled = drawSheet.inert || !pad.hasInk();
    showDrawStatus(cleared ? copy.RESIZE_CLEARED : null); // new ink makes an old message stale
    if (cleared) pad.showStartDot(true);
  },
});

// First sentence in bold, as in Draw.dc.html's too-short card.
function showDrawStatus(sentence) { showStatus(drawStatus, sentence); }
function showStatus(box, sentence) {
  box.hidden = !sentence;
  if (!sentence) return;
  box.classList.remove("shake");
  void box.offsetWidth; // replay the nudge for a second too-short in a row
  box.classList.add("shake");
  const cut = sentence.indexOf(".") + 1;
  box.querySelector("strong").textContent = sentence.slice(0, cut);
  box.querySelector("strong + span").textContent = sentence.slice(cut);
}

function newTrial() {
  const n = trials.length + 1;
  document.getElementById("draw-count").textContent = `Spiral ${n} of ${trialsWanted}`;
  const progress = document.getElementById("draw-progress");
  progress.innerHTML = Array.from({ length: trialsWanted }, (_, i) => (i < n ? `<span class="on${i === n - 1 ? " now" : ""}"></span>` : "<span></span>")).join("");
  progress.setAttribute("aria-valuemax", trialsWanted);
  progress.setAttribute("aria-valuenow", trials.length);
  progress.setAttribute("aria-valuetext", `${trials.length} of ${trialsWanted}`);
  pad.reset();
  pad.showStartDot(true);
  drawSheet.inert = false;
  drawDone.disabled = true;
  showDrawStatus(null);
}

onShow.draw = () => {
  trials = [];
  newTrial();
};

document.getElementById("draw-restart").addEventListener("click", newTrial); // this trial only

drawDone.addEventListener("click", async () => {
  const trace = pad.trace(choice.hand);
  let features;
  try {
    features = featuresFromTrace(trace);
  } catch {
    return showDrawStatus(copy.TOO_SHORT); // the ink stays so they can see what happened
  }
  trials.push({ trace, strokeStarts: pad.strokeStarts(), features });
  navigator.vibrate?.(12); // Android only; iOS ignores it
  if (trials.length < trialsWanted) {
    toast(copy.SPIRAL_SAVED(trials.length));
    drawSheet.classList.add("wipe"); // the finished spiral fades out, the next sheet fades in
    setTimeout(newTrial, reduced() ? 0 : 160);
    return;
  }

  // Scoring and saving are async: lock the pad so no new ink can reach
  // onInk and re-enable Done for a second trial or a second record.
  drawDone.disabled = true;
  drawSheet.inert = true;
  const finish = measuring();
  const { model, reference } = await scoring;
  const result = scoreSession(trials.map((t) => t.features), model, reference, choice.bracket);
  const record = {
    ts: Date.now(),
    task: "spiral",
    hand: choice.hand,
    ageChoice: choice.ageChoice,
    bracketChoice: choice.bracket,
    inputType: trials[0].trace.inputType,
    deviceLabel: trials[0].trace.deviceLabel,
    trials: trials.map(({ trace, strokeStarts, features }) => ({ samples: trace.samples, strokeStarts, features })),
    features: result.features,
    result,
  };
  try {
    await saveAssessment(record);
  } catch (err) {
    console.warn("NeuroTrace: couldn't save this check-in to history", err); // still show the result
  }
  const hide = await finish();
  current = record;
  location.hash = "#results";
  hide?.();
});

drawSheet.addEventListener("animationend", () => drawSheet.classList.remove("wipe"));

// A soft glow under the pen tip while it touches the sheet.
const penTip = el("span", "pen-tip");
drawSheet.append(penTip);
const canvasEl = document.getElementById("draw-pad");
const movePenTip = (e) => {
  const r = canvasEl.getBoundingClientRect();
  penTip.style.transform = `translate(${e.clientX - r.left}px, ${e.clientY - r.top}px)`;
};
canvasEl.addEventListener("pointerdown", (e) => { movePenTip(e); penTip.classList.add("on"); });
canvasEl.addEventListener("pointermove", movePenTip);
for (const type of ["pointerup", "pointercancel", "pointerleave"]) {
  canvasEl.addEventListener(type, () => penTip.classList.remove("on"));
}

// ---------- results ----------
// Renders a stored record, never a live computation: a check-in reopened from
// history reads exactly as it did the day it was made (Ruling 7). Nothing
// here may put result.score or result.scorePct on screen (Constraint 2).

const $ = (id) => document.getElementById(id);
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}
const card = (title, ...children) => {
  const c = el("section", "card result-card");
  c.append(el("h2", null, title), ...children);
  return c;
};
const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

const whenFmt = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });

function measureRow(key, frac) {
  const row = el("div", "measure");
  const track = el("div", "track");
  track.setAttribute("aria-hidden", "true"); // the sentence is the content; the dot is a second reading
  const dot = el("span", "track-dot");
  dot.style.setProperty("--p", `${Math.round(frac * 100)}%`);
  track.append(dot);
  // copy.measureSentence stays the one source of the wording; the number is
  // split out so it can count up as the dot travels.
  const [, lead, n, tail] = copy.measureSentence(key, frac).match(/^(.*?)(\d+)(%.*)$/);
  const sentence = el("span", "sub");
  const num = el("span", "num", n);
  sentence.append(lead, num, tail);
  row.dataset.n = n;
  row.append(el("span", "measure-name", copy.MEASURES[key].name), sentence, track);
  return row;
}

function levels(tier) {
  const wrap = el("div", "levels");
  wrap.setAttribute("role", "img");
  wrap.setAttribute("aria-label", `Result level: ${copy.TIER_SHORT[tier]}, ${tier + 1} of 3`);
  copy.TIER_SHORT.forEach((label, i) => {
    const step = el("span", i === tier ? "level on" : "level");
    step.append(el("span", "level-bar"), el("span", "level-label", label));
    wrap.append(step);
  });
  return wrap;
}

let drawing = null; // { canvas, prepared } for the replay button and theme redraws

function renderResults(rec) {
  const { result } = rec;
  const tier = copy.TIERS[result.tier];
  $("results-meta").textContent = `Spiral check-in · ${whenFmt.format(rec.ts)}`;
  $("results-title").textContent = tier.label;

  const shown = (key) => key in result.measurePct;
  const stoodOut = card("What stood out", el("p", "sub", copy.STOOD_OUT_CAPTION),
    ...result.topSignals.filter(shown).map((k) => measureRow(k, result.measurePct[k])));

  const every = card("Every measure", el("p", "sub", copy.EVERY_MEASURE_CAPTION));
  const scale = el("div", "scale-labels");
  scale.setAttribute("aria-hidden", "true");
  scale.append(el("span", null, "Lowest"), el("span", null, "Halfway"), el("span", null, "Highest"));
  every.append(scale);
  for (const g of copy.GROUPS) {
    const keys = SPIRAL_FEATURE_ORDER.filter((k) => copy.MEASURES[k].group === g.id && shown(k));
    if (!keys.length) continue;
    const group = el("div", "measure-group");
    group.append(el("h3", null, g.title), el("p", "sub", g.desc), ...keys.map((k) => measureRow(k, result.measurePct[k])));
    every.append(group);
  }

  $("results-body").replaceChildren(
    el("p", "summary", copy.RESULT_SUMMARY),
    levels(result.tier),
    el("p", "sub reference", copy.referenceSentence(result)),
    card("What this means", ...tier.meaning.map((p) => el("p", null, p))),
    stoodOut,
    card("What you can do", el("p", null, tier.todo)),
    drawingCard(rec),
    every,
  );
  reveal($("results-body").children);
  reveal($("results-body").querySelectorAll(".measure"), (row) => countUp(row.querySelector(".num"), Number(row.dataset.n)));
}

// ---------- your drawing: raw vs filtered, replay, speed ----------

function drawingCard(rec) {
  const drawn = (rec.trials ?? []).filter((t) => t.samples);
  const trial = drawn[0];
  drawing = null;
  if (!trial?.samples) return card("Your drawing", el("p", "sub", copy.DRAWING_PRUNED));

  const canvas = el("canvas", "drawing");
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", "Your recorded line drawn under the smoothed version the measures are taken from");
  const legend = el("div", "legend");
  for (const [cls, text] of [["swatch-raw", copy.RAW_LEGEND], ["swatch-filtered", copy.FILTERED_LEGEND]]) {
    const row = el("div", "legend-row");
    row.append(el("span", `swatch ${cls}`), el("span", null, text));
    legend.append(row);
  }
  const replay = el("button", "btn btn-secondary btn-compact");
  replay.type = "button";
  replay.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M7 4.5v15l13-7.5z"/></svg>Replay drawing';
  const speed = el("canvas", "speed");
  speed.setAttribute("role", "img");
  speed.setAttribute("aria-label", "Drawing speed over time");

  let prepared;
  try {
    prepared = prepareDrawing(trial);
  } catch (err) {
    console.warn("NeuroTrace: couldn't prepare the drawing", err);
    return card("Your drawing", el("p", "sub", copy.DRAWING_PRUNED));
  }
  drawing = { canvas, speed, prepared };
  replay.addEventListener("click", () => replayDrawing(drawing));
  // Painted once the card is in the document and has a size.
  requestAnimationFrame(() => paintDrawing(drawing));

  // With more than one spiral, a segmented pad picks which one is drawn.
  let picker = "";
  if (drawn.length > 1) {
    picker = el("div", "segmented");
    picker.setAttribute("role", "radiogroup");
    picker.setAttribute("aria-label", "Which spiral to show");
    picker.style.gridTemplateColumns = `repeat(${drawn.length}, minmax(0, 1fr))`;
    picker.style.setProperty("--n", drawn.length);
    drawn.forEach((_, i) => {
      picker.insertAdjacentHTML("beforeend",
        `<label class="segment"><input type="radio" name="which-spiral" value="${i}"${i ? "" : " checked"}><span>Spiral ${i + 1}</span></label>`);
    });
    picker.addEventListener("change", ({ target }) => {
      try {
        drawing.prepared = prepareDrawing(drawn[Number(target.value)]);
      } catch (err) {
        return console.warn("NeuroTrace: couldn't prepare that spiral", err);
      }
      cancelAnimationFrame(drawing.frame);
      paintDrawing(drawing);
    });
  }
  return card("Your drawing", picker, canvas, legend, replay, el("hr"),
    el("h3", null, "Speed along the line"), el("p", "sub", copy.SPEED_CAPTION), speed);
}

// Both lines go through normalize() - the centre-and-scale preprocessTrace
// applies - so they share one space and the only visible difference is the
// trimming, resampling and 15 Hz low-pass.
function prepareDrawing({ samples, strokeStarts }) {
  const t = Float64Array.from(samples, (s) => s.t);
  const x = Float64Array.from(samples, (s) => s.x);
  const y = Float64Array.from(samples, (s) => s.y);
  const raw = normalize(x, y);
  const filtered = preprocessTrace(t, x, y).slice(1);
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const [px, py] of [raw, filtered]) {
    for (let i = 0; i < px.length; i++) {
      if (px[i] < minX) minX = px[i];
      if (px[i] > maxX) maxX = px[i];
      if (py[i] < minY) minY = py[i];
      if (py[i] > maxY) maxY = py[i];
    }
  }
  const starts = new Set(strokeStarts ?? [0]);
  // Speed between neighbouring samples of the same stroke - a pen lift is not motion.
  const speeds = [];
  for (let i = 1; i < samples.length; i++) {
    const dt = samples[i].t - samples[i - 1].t;
    if (starts.has(i) || dt <= 0) continue;
    speeds.push(Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y) / dt);
  }
  return { t, raw, filtered, starts, speeds, box: { minX, maxX, minY, maxY } };
}

function fitCanvas(canvas) {
  const dpr = window.devicePixelRatio || 1;
  const { width, height } = canvas.getBoundingClientRect();
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { ctx, w: width, h: height };
}

function strokeLine(ctx, [px, py], map, n, starts, style, width) {
  ctx.save();
  ctx.strokeStyle = style;
  ctx.lineWidth = width;
  ctx.lineCap = ctx.lineJoin = "round";
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const [X, Y] = map(px[i], py[i]);
    if (i === 0 || starts?.has(i)) ctx.moveTo(X, Y); else ctx.lineTo(X, Y);
  }
  ctx.stroke();
  ctx.restore();
}

// upTo: seconds of the raw line to draw; the smoothed line appears once it is all drawn.
function paintDrawing(d, upTo = Infinity) {
  if (!d?.canvas.isConnected) return;
  const { ctx, w, h } = fitCanvas(d.canvas);
  const { raw, filtered, t, starts, box } = d.prepared;
  const pad = 16;
  const s = Math.min((w - 2 * pad) / (box.maxX - box.minX || 1), (h - 2 * pad) / (box.maxY - box.minY || 1));
  const ox = w / 2 - s * (box.minX + box.maxX) / 2, oy = h / 2 - s * (box.minY + box.maxY) / 2;
  const map = (x, y) => [ox + s * x, oy + s * y];
  let n = raw[0].length;
  if (upTo < Infinity) { n = 0; while (n < t.length && t[n] <= upTo) n++; }
  ctx.globalAlpha = 0.55;
  strokeLine(ctx, raw, map, n, starts, cssVar("--ink2"), 1.5);
  ctx.globalAlpha = 1;
  if (n === raw[0].length) strokeLine(ctx, filtered, map, filtered[0].length, null, cssVar("--accent"), 3);
  if (upTo === Infinity) paintSpeed(d);
}

function paintSpeed({ speed, prepared: { speeds } }) {
  const { ctx, w, h } = fitCanvas(speed);
  if (speeds.length < 2) return;
  let top = 1;
  for (const v of speeds) if (v > top) top = v; // no Math.max(...arr) on long traces (Constraint 6)
  const X = (i) => (i / (speeds.length - 1)) * w, Y = (v) => h - 4 - (v / top) * (h - 8);
  ctx.beginPath();
  ctx.moveTo(0, h);
  speeds.forEach((v, i) => ctx.lineTo(X(i), Y(v)));
  ctx.lineTo(w, h);
  ctx.closePath();
  ctx.fillStyle = cssVar("--accent-soft");
  ctx.fill();
  ctx.beginPath();
  speeds.forEach((v, i) => (i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v))));
  ctx.strokeStyle = cssVar("--accent");
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  ctx.stroke();
}

// Always animates: the person asked for it with a button (Constraint 8).
function replayDrawing(d) {
  cancelAnimationFrame(d.frame);
  const end = d.prepared.t[d.prepared.t.length - 1];
  const start = performance.now();
  const step = (now) => {
    const elapsed = (now - start) / 1000;
    paintDrawing(d, elapsed >= end ? Infinity : elapsed);
    if (elapsed < end) d.frame = requestAnimationFrame(step);
  };
  d.frame = requestAnimationFrame(step);
}

matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => paintDrawing(drawing));

onShow.results = async (id) => {
  if (id) {
    const rec = await getAssessment(Number(id)).catch(() => null);
    if (!rec?.result) return location.replace("#home");
    current = rec;
  }
  renderResults(current);
  $("results-title").focus({ preventScroll: true });
};

// ---------- home: history ----------

function historyWhen(ts) {
  const d = new Date(ts), today = new Date();
  const time = d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  const days = Math.round((new Date(today.toDateString()) - new Date(d.toDateString())) / 864e5);
  if (days === 0) return `Today, ${time}`;
  if (days === 1) return `Yesterday, ${time}`;
  return `${d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "short" })}, ${time}`;
}

const historyEmpty = document.querySelector("#history .empty"); // index.html's empty state

onShow.home = async () => {
  const records = await listAssessments().catch((err) => {
    console.warn("NeuroTrace: couldn't read history", err);
    return [];
  });
  if (!records.length) return $("history").replaceChildren(historyEmpty);
  const list = el("div", "card history-list");
  for (const rec of records) {
    const row = el("a", "history-row");
    row.href = `#results/${rec.id}`;
    const text = el("span", "history-text");
    text.append(el("span", "history-when", historyWhen(rec.ts)), el("span", "sub", copy.TIERS[rec.result.tier].label));
    row.append(text);
    row.insertAdjacentHTML("beforeend", '<svg class="icon chevron" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>');
    list.append(row);
  }
  $("history").replaceChildren(list);
};

// ---------- collection mode (handoff B2, docs/COLLECTED_FORMAT.md) ----------
// A facilitator records three spirals per participant for the device-matched
// reference. Nothing is scored or shown; each session is saved on the iPad
// and leaves it only through Export.

const COLLECT_TRIALS = 3;
let pendingId = null; // the ID offered to the next new participant

function startSession(subjectId, session) {
  collecting = { subjectId, session, trials: [] };
  location.hash = "#collect-details";
}

onShow.collect = async () => {
  let subs = [], sessions = [];
  try {
    [subs, sessions] = await Promise.all([subjects(), listCollected()]);
  } catch (err) {
    console.warn("NeuroTrace: couldn't read collected sessions", err);
  }
  collecting = null;
  pendingId = newSubjectId(new Set(subs.map((s) => s.subjectId)));
  $("collect-new-id").textContent = pendingId;

  const list = $("collect-returning");
  if (!subs.length) list.replaceChildren(el("p", "sub", copy.NO_PARTICIPANTS));
  else {
    const dateFmt = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" });
    list.replaceChildren(...subs.map(({ subjectId, sessions: n, lastAt }) => {
      const row = el("button", "history-row returning-row");
      row.type = "button";
      const text = el("span", "history-text");
      text.append(el("span", "history-when mono", subjectId),
        el("span", "sub", `${n} session${n === 1 ? "" : "s"}, last on ${dateFmt.format(new Date(lastAt))}`));
      row.append(text);
      row.insertAdjacentHTML("beforeend", '<svg class="icon chevron" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>');
      row.addEventListener("click", () => startSession(subjectId, n + 1));
      return row;
    }));
  }

  const waiting = sessions.filter((s) => !s.exported);
  $("collect-unexported").hidden = !waiting.length;
  $("unexported-title").textContent = `${waiting.length} session${waiting.length === 1 ? "" : "s"} not exported yet`;
};
$("collect-start").addEventListener("click", () => startSession(pendingId, 1));
$("collect-export-all").addEventListener("click", async () => {
  const waiting = (await listCollected()).filter((s) => !s.exported);
  if (!waiting.length) return;
  const day = new Date().toISOString().slice(0, 10);
  if (await exportSessions(waiting, `neurotrace-export-${day}.json`)) onShow.collect();
});

// ---- details: consent, age, hand, diagnosis (in that order) ----

const detailsHelp = $("details-help");
const detailsBegin = $("details-begin");
const radio = (name) => document.querySelector(`#details-form input[name="${name}"]:checked`)?.value;

function readDetails() {
  const age = Number($("c-age").value);
  const med = $("c-med").value;
  const dx = radio("c-dx");
  return {
    consent: $("c-consent").checked,
    age: Number.isInteger(age) && age >= 18 && age <= 110 ? age : null,
    hand: radio("c-hand"),
    diagnosis: dx,
    medicationHoursAgo: dx === "parkinsons" && med !== "" && Number(med) >= 0 ? Number(med) : null,
  };
}

function syncDetails() {
  const d = readDetails();
  $("c-bracket").textContent = d.age ? copy.bracketNote(d.age) : "";
  $("c-med-row").hidden = d.diagnosis !== "parkinsons";
  const missing = [!d.consent && "consent", !d.age && "an age from 18 to 110", !d.hand && "the drawing hand", !d.diagnosis && "a diagnosis"].filter(Boolean);
  detailsBegin.disabled = missing.length > 0;
  detailsHelp.hidden = !missing.length;
  detailsHelp.textContent = missing.length ? `Still needed: ${missing.join(", ")}.` : "";
}

onShow["collect-details"] = () => {
  $("details-session").innerHTML = `<span class="mono">${collecting.subjectId}</span>, session ${collecting.session}`;
  if (collecting.details) return syncDetails(); // coming back from the spirals keeps the answers
  $("c-consent").checked = false;
  $("c-age").value = "";
  $("c-med").value = "";
  document.querySelectorAll("#details-form input[type=radio]").forEach((r) => (r.checked = false));
  syncDetails();
};
$("details-form").addEventListener("input", syncDetails);
$("details-form").addEventListener("change", syncDetails);
detailsBegin.addEventListener("click", () => {
  collecting.details = readDetails();
  collecting.trials = [];
  location.hash = "#collect-draw";
});

// ---- three spirals ----

const collectNext = $("collect-next");
const collectStatus = $("collect-status");
const collectSheet = $("collect-pad").parentElement;
const collectPad = createPad($("collect-pad"), {
  onInk({ cleared }) {
    collectNext.disabled = collectSheet.inert || !collectPad.hasInk();
    showStatus(collectStatus, cleared ? copy.RESIZE_CLEARED : null);
    if (cleared) collectPad.showStartDot(true);
  },
});

function newCollectTrial() {
  const done = collecting.trials.length, n = done + 1;
  $("collect-count").textContent = `Spiral ${n} of ${COLLECT_TRIALS}`;
  $("collect-session").innerHTML = `<span class="mono">${collecting.subjectId}</span>, session ${collecting.session}`;
  const progress = $("collect-progress");
  progress.innerHTML = Array.from({ length: COLLECT_TRIALS }, (_, i) => (i < n ? `<span class="on${i === n - 1 ? " now" : ""}"></span>` : "<span></span>")).join("");
  progress.setAttribute("aria-valuenow", done);
  progress.setAttribute("aria-valuetext", `${done} of ${COLLECT_TRIALS}`);
  collectNext.textContent = n === COLLECT_TRIALS ? "Finish" : "Next spiral";
  collectPad.reset();
  collectPad.showStartDot(true);
  collectSheet.inert = false;
  collectNext.disabled = true;
  showStatus(collectStatus, null);
}

onShow["collect-draw"] = () => {
  if (!collecting.details) return location.replace("#collect-details");
  collecting.trials = [];
  newCollectTrial();
};

$("collect-redo").addEventListener("click", newCollectTrial);
$("collect-back").addEventListener("click", (e) => {
  const drawnSome = collecting?.trials.length || collectPad.hasInk();
  if (drawnSome && !confirm(copy.LEAVE_SESSION)) e.preventDefault();
});

collectNext.addEventListener("click", async () => {
  const trace = collectPad.trace(collecting.details.hand);
  try {
    featuresFromTrace(trace); // validity only - nothing is scored or kept from this
  } catch {
    return showStatus(collectStatus, copy.TOO_SHORT);
  }
  collecting.trials.push(trace);
  navigator.vibrate?.(12);
  if (collecting.trials.length < COLLECT_TRIALS) {
    toast(copy.SPIRAL_SAVED(collecting.trials.length));
    return newCollectTrial();
  }

  collectNext.disabled = true;
  collectSheet.inert = true;
  const { subjectId, session, details, trials: traces } = collecting;
  const record = {
    formatVersion: 1,
    subjectId,
    session,
    collectedAt: new Date().toISOString(),
    deviceLabel: traces[0].deviceLabel,
    inputType: traces[0].inputType,
    hand: details.hand,
    age: details.age,
    diagnosis: details.diagnosis,
    medicationHoursAgo: details.medicationHoursAgo,
    consent: true,
    trials: traces.map((tr, i) => ({
      trial: i + 1,
      task: "spiral",
      samples: tr.samples.map(({ t, x, y, pressure }) => ({ t, x, y, pressure })),
    })),
    exported: false,
  };
  try {
    record.id = await saveCollected(record);
  } catch (err) {
    // Losing a participant's spirals is the one failure that matters here:
    // keep the session in memory so it can still be exported by hand.
    console.error("NeuroTrace: couldn't save the session on this iPad", err);
  }
  collecting.saved = record;
  location.hash = "#collect-done";
});

// ---- done: summary and export ----

onShow["collect-done"] = () => {
  const s = collecting.saved;
  if (!s) return location.replace("#collect");
  const facts = [["Participant", s.subjectId], ["Session", String(s.session)], ["Age", String(s.age)],
    ["Drawing hand", s.hand === "left" ? "Left" : "Right"], ["Diagnosis", copy.DIAGNOSES[s.diagnosis]],
    ["Input", { pencil: "Apple Pencil", touch: "Finger", mouse: "Mouse" }[s.inputType] ?? s.inputType]];
  const grid = el("dl", "card facts");
  for (const [k, v] of facts) {
    const cell = el("div");
    cell.append(el("dt", "sub", k), el("dd", null, v));
    grid.append(cell);
  }
  $("done-summary").replaceChildren(grid);
};
$("done-export").addEventListener("click", async () => {
  const s = collecting?.saved;
  if (s) await exportSessions([s], `${s.subjectId}-s${s.session}.json`);
});

// The share sheet where there is one (AirDrop, Files, Mail on iPad),
// otherwise a download. One session exports as an object, several as an
// array - both shapes collected.py reads.
async function exportSessions(sessions, filename) {
  const clean = sessions.map(({ id, exported, ...s }) => s);
  const file = new File([JSON.stringify(clean.length === 1 ? clean[0] : clean, null, 2)], filename, { type: "application/json" });
  try {
    if (navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: filename });
    else download(file);
  } catch (err) {
    if (err.name === "AbortError") return false; // they closed the share sheet
    download(file);
  }
  const ids = sessions.map((s) => s.id).filter((id) => id != null);
  if (ids.length) await markExported(ids).catch((err) => console.warn("NeuroTrace: couldn't mark sessions exported", err));
  toast(copy.EXPORTED);
  return true;
}

function download(file) {
  const url = URL.createObjectURL(file);
  const a = el("a");
  a.href = url;
  a.download = file.name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ---------- settings ----------

// "auto" leaves the choice to prefers-color-scheme; light/dark pin it via
// data-theme, which styles.css keys the token sets to.
function applyTheme(theme) {
  if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
  else delete document.documentElement.dataset.theme;
}

$("settings-age").innerHTML = copy.AGE_CHOICES
  .map(({ label }) => `<label class="chip"><input type="radio" name="s-age" value="${label}"><span>${label}</span></label>`)
  .join("");

const check = (name, value) =>
  document.querySelectorAll(`#screen-settings input[name="${name}"]`).forEach((r) => (r.checked = r.value === value));

// Order matches copy.ACCENTS; styles.css holds each accent's light and dark values.
const ACCENT_IDS = ["blue", "indigo", "violet", "teal", "amber", "rose", "graphite"];
$("accent-choices").innerHTML = copy.ACCENTS
  .map((name, i) => `<label class="accent-option" data-accent="${ACCENT_IDS[i]}"><input type="radio" name="accent" value="${ACCENT_IDS[i]}" aria-label="${name}"><span class="accent-dot"></span></label>`)
  .join("");

const accentName = (id) => copy.ACCENTS[Math.max(0, ACCENT_IDS.indexOf(id))];

function applyAccent(accent) {
  if (accent && accent !== "blue") document.documentElement.dataset.accent = accent;
  else delete document.documentElement.dataset.accent;
}

onShow.settings = () => {
  const { ageChoice, hand, theme, accent, motion } = getPrefs();
  check("s-age", ageChoice);
  check("s-hand", hand);
  check("theme", theme);
  check("accent", accent);
  $("accent-current").textContent = accentName(accent);
  check("motion", motion);
  $("delete-status").textContent = "";
};

// Every change saves at once - there is no Save button to forget.
// A new theme or accent spreads out from the control that was tapped.
$("screen-settings").addEventListener("change", ({ target }) => {
  const { value } = target;
  const r = target.closest("label").getBoundingClientRect();
  const from = { kind: "theme", x: r.left + r.width / 2, y: r.top + r.height / 2 };
  if (target.name === "s-age") setPrefs({ ageChoice: value });
  if (target.name === "s-hand") setPrefs({ hand: value });
  if (target.name === "theme") {
    setPrefs({ theme: value });
    swap(() => applyTheme(value), from);
  }
  if (target.name === "accent") {
    setPrefs({ accent: value });
    $("accent-current").textContent = accentName(value);
    swap(() => applyAccent(value), from);
  }
  if (target.name === "motion") {
    setPrefs({ motion: value });
    applyMotion(value);
  }
  toast(copy.SAVED);
});

$("delete-all").addEventListener("click", async () => {
  if (!confirm(copy.DELETE_CONFIRM)) return;
  try {
    await clearAssessments();
    current = null;
    $("delete-status").textContent = copy.DELETED;
  } catch (err) {
    console.warn("NeuroTrace: couldn't delete check-ins", err);
    $("delete-status").textContent = copy.DELETE_FAILED;
  }
});

// ---------- about ----------

$("how-steps").replaceChildren(...copy.HOW_STEPS.map((step) => el("li", null, step)));

onShow["about-app"] = async () => {
  try {
    const { reference } = await scoring;
    const all = reference.brackets.all;
    $("about-reference").textContent = copy.referenceSentence({
      referenceN: all.n, bracketKey: "all", deviceMatched: reference.deviceMatched === true,
    });
    $("about-reference").hidden = false;
  } catch {
    $("about-reference").hidden = true; // no reference file, nothing honest to say here
  }
};

applyTheme(getPrefs().theme);
applyAccent(getPrefs().accent);
applyMotion(getPrefs().motion);
matchMedia("(prefers-reduced-motion: reduce)").addEventListener("change", () => applyMotion(getPrefs().motion));

// ---------- motion setup ----------

const tabbarEl = $("tabbar");
addEventListener("resize", () => moveLens(tabbarEl));
$("measuring-steps").replaceChildren(...copy.MEASURE_STEPS.map((step) => el("li", null, step)));
mountMascots();
// The welcome pen dot is SMIL, which CSS can't stop - pause it by hand.
if (reduced()) document.querySelectorAll(".hero svg").forEach((svg) => svg.pauseAnimations());

// ---------- error ----------

onShow.error = () => {
  document.getElementById("error-message").textContent = loadError.message;
};

// ---------- init ----------

// data-copy="KEY [KEY …]" -> the copy.js sentences, joined with a space.
document.querySelectorAll("[data-copy]").forEach((el) => {
  el.textContent = el.dataset.copy.split(" ").map((key) => copy[key]).join(" ");
});
drawArt();
addEventListener("hashchange", route);
route();
