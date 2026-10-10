// app shell: a hash router over the <section class="screen"> elements in
// index.html. signed out there's only the home page; signed in, the five tabs
// (dashboard, testing, training, progress, settings), the check-in flow
// (consent -> about you -> draw -> results) and collection mode.
// scoring lives in score.js, every sentence in copy.js, storage in store.js.

import { SPIRAL_FEATURE_ORDER, featuresFromTrace, normalize, preprocessTrace } from "./nt-features.js";
import { checkScoringFiles, scoreSession } from "./score.js";
import * as copy from "./copy.js";
import { getPrefs, setPrefs, saveAssessment, listAssessments, getAssessment, clearAssessments, saveCollected, listCollected, markExported, subjects, newSubjectId, saveTrainingTry, listTrainingTries, getTrainingState, setTrainingState } from "./store.js";
import {
  EXERCISES, HITS_TO_LEVEL_UP, MISSES_TO_LEVEL_DOWN, newLevelState, applyTry, tooHard, scoreBigWriting,
  pointAlong, tracingPath, scoreTracing, TRACE_LIMIT, rhythmPath, scoreRhythm, RHYTHM_BEATS, COUNT_IN, RHYTHM_LAG, RHYTHM_NEAR,
  scoreTargets, targetRadius, TARGETS, CATCH_SHARE, TAP_PRECISION,
} from "./train.js";
import { createPad, spiralPoints } from "./pad.js";
import { reduced, applyMotion, swap, moveLens, reveal, countUp, watchTitle, toast, mountMascots, measuring } from "./motion.js";

// ---------- spiral art (the guide spiral itself is pad.js's spiralPoints) ----------

// a believable hand-drawn line for the home hero and check-in art: the guide spiral
// pushed in and out along its radius by a slow wobble plus a little jitter,
// faded in over the first fifth so it starts on the centre. same recipe as
// the design canvas so the art matches the mockups.
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
// every piece of art is a 340 × 340 viewBox centred on (170, 170), the
// geometry the design canvas used. CSS sets stroke widths per place.

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
// both files sit next to index.html. loaded once, eagerly, so a mismatched or
// missing model shows up the moment anyone needs scoring. a model handed
// numbers in positions its weights don't expect has no safe way to score, so
// the router sends every scoring path to the error screen instead
// (Global Constraint 4). scoring code reads `const { model, reference } = await scoring`.

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
// location.hash is "#<screen>[/<param>]", e.g. "#dashboard" or "#results/12".

let previous = null; // the screen shown before this one

function resolve(name, param) {
  const prefs = getPrefs();
  // when signed out, only the home page exists as well as consent (the first step of logging in).
  if (!prefs.signedIn) return name === "consent" ? name : "home";
  if (!name || name === "home" || !document.getElementById(`screen-${name}`)) return "dashboard";
  if (name === "error") return loadError ? name : "dashboard";
  // collection mode is run by a facilitator, not the person on the personal
  // consent flow, so it has its own gate.
  if (name.startsWith("collect")) return name === "collect" || collecting ? name : "collect";
  if (!prefs.consented && name !== "consent") return "consent";
  if (name === "draw" && !choice) return "about";
  // #results/<id> loads from history
  if (name === "exercise" && !EXERCISES[param]?.built) return "training"; // only built exercises open
  if (name === "results" && !current && !param) return "dashboard"; // #results/<id> loads from history, moved it here since the homescreen isnt available for logged-in users
  return name;
}

async function route() {
  const hash = location.hash;
  const [name, param] = hash.slice(1).split("/");
  const target = resolve(name, param);
  if (target !== name) return location.replace(`#${target}`); // fires hashchange -> route again

  if (name === "draw" || name === "results" || name === "progress") {
    try {
      await scoring;
    } catch {
      return location.replace("#error");
    }
    if (location.hash !== hash) return; // the user moved on while the files loaded
  }
  show(name, param);
}

// per-screen setup, run each time the screen is shown.
const onShow = {};
const TABS = new Set(["dashboard", "testing", "training", "progress", "settings"]);
const TAB_ORDER = ["dashboard", "testing", "training", "progress", "settings"];

const TITLED = new Set([...TAB_ORDER, "results"]); // screens whose large title collapses on scroll

// tabs slide towards the tab you picked, everything else rises into place.
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
  // the tab bar is for the five tab screens only. A check-in or a
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
  setPrefs({ consented: true, onboarded: true, signedIn: true });
  location.hash = "#dashboard";
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
  // back to whichever tab started the check-in (Dashboard or Testing).
  document.getElementById("about-back").href = TABS.has(previous) ? `#${previous}` : "#testing";
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
// one check-in is three spirals, averaged (handoff §6: averaging three
// drawings cuts within-person noise). collection mode also records three, so
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

// first sentence in bold, like Draw.dc.html's too-short card.
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

  // scoring and saving are async - lock the pad so no new ink can reach
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
    trials: trials.map(({ trace, strokeStarts, features }) => ({
      samples: trace.samples, strokeStarts, features, path: replayPath(trace.samples, strokeStarts),
    })),
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

// a soft glow under the pen tip while it touches the sheet.
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
// renders a stored record, never a live computation, so a check-in reopened from
// history reads exactly as it did the day it was made (Ruling 7). nothing
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
  track.setAttribute("aria-hidden", "true"); // the sentence is the content, the dot is a second reading
  const dot = el("span", "track-dot");
  dot.style.setProperty("--p", `${Math.round(frac * 100)}%`);
  track.append(dot);
  // copy.measureSentence stays the one source of the wording, the number is
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

  const parts = [
    el("p", "summary", copy.RESULT_SUMMARY),
    levels(result.tier),
    el("p", "sub reference", copy.referenceSentence(result)),
    card("What this means", ...tier.meaning.map((p) => el("p", null, p))),
    stoodOut,
    card("What you can do", el("p", null, tier.todo)),
    drawingCard(rec),
    every,
  ];
  // two columns on iPad: the reading on the left, the measures on the right.
  // on a phone both wrappers are display: contents and `order` keeps this
  // exact sequence.
  parts.forEach((node, i) => (node.style.order = i));
  const main = el("div", "results-main"), side = el("div", "results-side");
  main.append(...parts.filter((n) => n !== stoodOut && n !== every));
  side.append(stoodOut, every);
  $("results-body").replaceChildren(main, side);
  reveal(parts);
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
  // painted once the card is in the document and has a size.
  requestAnimationFrame(() => paintDrawing(drawing));

  // with more than one spiral, a segmented pad picks which one gets drawn.
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

// both lines go through normalize() - the centre-and-scale preprocessTrace
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
  // speed between neighbouring samples of the same stroke - a pen lift isn't motion.
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

// upTo: seconds of the raw line to draw. the smoothed line shows up once it's all drawn.
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

// always animates bc the person asked for it with a button (Constraint 8).
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
    if (!rec?.result) return location.replace("#dashboard");
    current = rec;
  }
  renderResults(current);
  $("results-title").focus({ preventScroll: true });
};

// ---------- dashboard: history ----------

function historyWhen(ts) {
  const d = new Date(ts), today = new Date();
  const time = d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  const days = Math.round((new Date(today.toDateString()) - new Date(d.toDateString())) / 864e5);
  if (days === 0) return `Today, ${time}`;
  if (days === 1) return `Yesterday, ${time}`;
  return `${d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "short" })}, ${time}`;
}

const historyEmpty = document.querySelector("#history .empty"); // index.html's empty state

onShow.dashboard = async () => {
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

// ---------- progress: first vs latest check-in ----------

// both of these are scored from the stored features with today's reference
// so an update in the reference doesn't show up as a change in the person. only check-ins
// with the latest one's hand and input count (another hand or a finger instead
// of the pencil or stylus is a different movement)

const sameSetup = (a, b) => a.hand === b.hand && a.inputType === b.inputType;

function compareRow(key, first, latest) {
  const row = el("div", "measure");
  const track = el("div", "track");
  track.setAttribute("aria-hidden", "true"); // the sentences are the content
  for (const [frac, cls] of [[first, "track-dot then"], [latest, "track-dot"]]) {
    const dot = el("span", cls);
    dot.style.setProperty("--p", `${Math.round(frac * 100)}%`);
    track.append(dot);
  }
  row.append(el("span", "measure-name", copy.MEASURES[key].name),
    el("span", "sub", `First: ${copy.measureSentence(key, first)}`),
    el("span", "sub", `Latest: ${copy.measureSentence(key, latest)}`),
    track);
  return row;
}



// this creates a copy of the drawing for replay and they are saved for check-ins
// (the full drawing is only kept for the newest three drawings, see RAW_KEEP in store.js).
// keeps an existing sample once at least 1/60 s has passed since the last kept one.
// stroke starts and ends are always kept.

const REPLAY_HZ = 60;
function replayPath(samples, strokeStarts = [0]) {
  const starts = new Set(strokeStarts);
  const keep = [];
  let last = -Infinity;
  samples.forEach((s, i) => {
    const edge = starts.has(i) || starts.has(i + 1) || i === samples.length - 1;
    if (edge || s.t - last >= 1 / REPLAY_HZ) {
      keep.push(i);
      last = s.t;
    }
  });
  const pick = (k) => Float32Array.from(keep, (i) => samples[i][k]);
  return { t: pick("t"), x: pick("x"), y: pick("y"), starts: keep.flatMap((i, j) => (starts.has(i) ? [j] : [])) };
}

// drawing to replay for a check-in. uses its saved replay copy (older
// check-ins don't have one, so one is built from the full drawing instead).
// returns null if the full drawing was already deleted.

function checkinPath(rec) {
  const trial = (rec.trials ?? []).find((t) => t.path || t.samples);
  if (!trial) return null;
  return trial.path ?? replayPath(trial.samples, trial.strokeStarts);
}

// a result card with the date, tier and saved drawing. keeps the canvas
// and path together so the drawing can be replayed.
function snapshot(label, rec, result) {
  const box = el("section", "card snapshot");
  box.append(el("span", "sub", label), el("h2", "card-title", whenFmt.format(rec.ts)), el("p", null, copy.TIERS[result.tier].label));
  const path = checkinPath(rec);
  if (!path?.t.length) {
    box.append(el("p", "sub", copy.REPLAY_MISSING));
    return { box, live: null };
  }
  const canvas = el("canvas", "thumb");
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", `Your spiral from ${whenFmt.format(rec.ts)}`);
  box.append(canvas, el("p", "sub", copy.drawnIn(path.t[path.t.length - 1])));
  return { box, live: { canvas, path } };
}

// fits the saved drawing to the canvas and draws up to `upTo` seconds.
// pen lifts stay separate; a dot follows the tip while it's still drawing.
function paintPath({ canvas, path }, upTo = Infinity) {
  if (!canvas.isConnected) return;
  const { ctx, w, h } = fitCanvas(canvas);
  if (!w) return; // screen hidden mid-replay
  const { t, x, y, starts } = path;
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (let i = 0; i < x.length; i++) {
    if (x[i] < minX) minX = x[i];
    if (x[i] > maxX) maxX = x[i];
    if (y[i] < minY) minY = y[i];
    if (y[i] > maxY) maxY = y[i];
  }
  const pad = 10;
  // keeps the proportions. uses 1 for a flat axis so division by 0 doesn't happen
  const s = Math.min((w - 2 * pad) / (maxX - minX || 1), (h - 2 * pad) / (maxY - minY || 1));
  const ox = w / 2 - s * (minX + maxX) / 2, oy = h / 2 - s * (minY + maxY) / 2;
  const lifts = new Set(starts);
  let n = 0;
  while (n < t.length && t[n] <= upTo) n++;
  ctx.strokeStyle = ctx.fillStyle = cssVar("--accent");
  ctx.lineWidth = 2;
  ctx.lineCap = ctx.lineJoin = "round";
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const X = ox + s * x[i], Y = oy + s * y[i];
    // starts a new stroke on each pen lift instead of joining across the gap
    if (i === 0 || lifts.has(i)) ctx.moveTo(X, Y); else ctx.lineTo(X, Y);
  }
  ctx.stroke();
  if (n > 0 && n < t.length) {
    ctx.beginPath();
    ctx.arc(ox + s * x[n - 1], oy + s * y[n - 1], 4, 0, 2 * Math.PI);
    ctx.fill();
  }
}

// every drawing starts together and runs at the speed it was drawn,
// so a drawing that took longer finishes later.
let progressFrame = 0;
function replayAll(lives) {
  cancelAnimationFrame(progressFrame);
  const end = lives.reduce((m, l) => Math.max(m, l.path.t[l.path.t.length - 1]), 0);
  const start = performance.now();
  const step = (now) => {
    const elapsed = (now - start) / 1000;
    lives.forEach((l) => paintPath(l, elapsed));
    if (elapsed < end && lives.some((l) => l.canvas.isConnected)) progressFrame = requestAnimationFrame(step);
  };
  progressFrame = requestAnimationFrame(step);
}

onShow.progress = async () => {
  const body = $("progress-body");
  const records = await listAssessments().catch(() => []); // newest first
  const latest = records[0];
  // records are newest first, so the last matching check-in is the earliest.
  const first = latest && records.filter((r) => sameSetup(r, latest)).at(-1);
  if (!first || first === latest) {
    const empty = el("div", "card empty");
    const mascot = el("span", "empty-mascot");
    mascot.dataset.mascot = "idle";
    empty.append(mascot, el("p", null, copy.PROGRESS_EMPTY));
    mountMascots(empty);
    return body.replaceChildren(empty);
  }
  const { model, reference } = await scoring;
  // one ruler for both: today's reference, the latest check-in's age group.
  const place = (rec) => scoreSession([rec.features ?? rec.result.features], model, reference, latest.bracketChoice);
  const a = place(first), b = place(latest);

  const one = snapshot("First check-in", first, a), two = snapshot("Latest check-in", latest, b);
  const pair = el("div", "snapshot-pair");
  pair.append(one.box, two.box);
  const lives = [one.live, two.live].filter(Boolean);
  const replay = el("button", "btn btn-secondary btn-compact replay-both");
  replay.type = "button";
  replay.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M7 4.5v15l13-7.5z"/></svg>' +
    (lives.length > 1 ? "Replay both" : "Replay drawing");
  replay.addEventListener("click", () => replayAll(lives)); // always animates: the person asked for it

  const key = el("div", "dot-legend");
  key.setAttribute("aria-hidden", "true");
  for (const [cls, text] of [["legend-key then", "First"], ["legend-key", "Latest"]]) {
    const item = el("span");
    item.append(el("span", cls), text);
    key.append(item);
  }
  const measures = card("Measure by measure", el("p", "sub", copy.PROGRESS_CAPTION), key);
  const shown = (k) => k in a.measurePct && k in b.measurePct;
  for (const g of copy.GROUPS) {
    const keys = SPIRAL_FEATURE_ORDER.filter((k) => copy.MEASURES[k].group === g.id && shown(k));
    if (!keys.length) continue;
    const group = el("div", "measure-group");
    group.append(el("h3", null, g.title), ...keys.map((k) => compareRow(k, a.measurePct[k], b.measurePct[k])));
    measures.append(group);
  }
  body.replaceChildren(el("p", "sub progress-meta", copy.progressSetup(latest.hand, latest.inputType)), pair, ...(lives.length ? [replay] : []), measures);
  // plays once on arrival. under reduced motion the finished drawings show instead.
  requestAnimationFrame(() => (reduced() ? lives.forEach((l) => paintPath(l)) : replayAll(lives)));
};

// ---------- training: the tab ----------
// each exercise card shows its real level. exercises not built yet say so.

onShow.training = () => {
  for (const btn of document.querySelectorAll("#screen-training [data-exercise]")) {
    const id = btn.dataset.exercise;
    const [level, note] = btn.querySelectorAll(".sub");
    if (!EXERCISES[id].built) {
      level.textContent = copy.COMING_SOON;
      note.textContent = "";
      continue;
    }
    const state = getTrainingState(id);
    level.textContent = copy.levelShort((state?.level ?? 0) + 1);
    note.textContent = !state ? copy.NOT_STARTED : copy.LAST_CHANGE[state.last] ?? copy.hitsSoFar(state.hits, HITS_TO_LEVEL_UP);
  }
};
document.querySelectorAll("#screen-training [data-exercise]").forEach((btn) => btn.addEventListener("click", () => {
  const id = btn.dataset.exercise;
  if (EXERCISES[id].built) location.hash = `#exercise/${id}`;
  else toast(copy.NOT_BUILT);
}));

// ---------- training: the exercise screen ----------
// one exercise at a time. each try is measured (train.js), shown straight
// away, saved, and moves the level by the agreed rule: 3 hits up, 3 misses in
// a row down, "too hard today" down any time. EX_UI (below) says how each
// exercise draws, starts and is scored.

const exSheet = $("ex-pad").parentElement;
const tapCanvas = $("ex-tap");
const tapSheet = tapCanvas.parentElement;
let ex = null; // the exercise on screen: { id, state, levels } plus the try in progress
const exTarget = () => ex.levels[ex.state.level];
const exUI = () => EX_UI[ex.id];

// the timers, animation frame and metronome clicks of the try in progress,
// kept so they all stop together - on a new try, Done or leaving the screen.
let exTimers = [], exFrame = 0, exClicks = [];
function exStop() {
  exTimers.forEach(clearTimeout);
  exTimers = [];
  cancelAnimationFrame(exFrame);
  for (const o of exClicks) {
    try { o.stop(); } catch {}
  }
  exClicks = [];
}
const exAfter = (ms, fn) => exTimers.push(setTimeout(fn, ms));
addEventListener("hashchange", () => { if (!location.hash.startsWith("#exercise")) exStop(); });

const exPhase = (text) => ($("ex-phase").textContent = text ?? "");

// which buttons show: "draw" (Start over + Done), "start" (Start), "next" (Next try), or none.
function exActions(which) {
  $("ex-draw-actions").hidden = which !== "draw";
  $("ex-start-actions").hidden = which !== "start";
  $("ex-next-actions").hidden = which !== "next";
}

function strokePath(ctx, path, upTo = path.x.length) {
  ctx.beginPath();
  for (let i = 0; i < upTo; i++) {
    if (i === 0) ctx.moveTo(path.x[i], path.y[i]);
    else ctx.lineTo(path.x[i], path.y[i]);
  }
  ctx.stroke();
}

function dot(ctx, x, y, r) {
  ctx.fillStyle = cssVar("--accent");
  ctx.beginPath();
  ctx.arc(x, y, r, 0, 2 * Math.PI);
  ctx.fill();
}

// ---- big writing ----

// the writing area: the baseline at 80% of its height, the target line the
// level's share of the height above it.
function writingGeometry(w, h, share) {
  const baselineY = h * 0.8;
  return { baselineY, targetPx: h * share, targetY: baselineY - h * share, left: w * 0.06, right: w * 0.94 };
}

function bigWritingGuide(ctx, w, h) {
  const g = writingGeometry(w, h, exTarget());
  ctx.save();
  ctx.lineWidth = 2;
  ctx.strokeStyle = cssVar("--guide");
  ctx.beginPath();
  ctx.moveTo(g.left, g.baselineY);
  ctx.lineTo(g.right, g.baselineY);
  ctx.stroke();
  ctx.setLineDash([10, 8]);
  ctx.strokeStyle = cssVar("--accent");
  ctx.beginPath();
  ctx.moveTo(g.left, g.targetY);
  ctx.lineTo(g.right, g.targetY);
  ctx.stroke();
  ctx.fillStyle = cssVar("--ink2");
  ctx.font = `600 15px ${cssVar("--font-body")}`;
  // at the right end: writing starts on the left, so it covers the label last.
  ctx.textAlign = "right";
  ctx.fillText(copy.TARGET_LABEL, g.right, g.targetY - 10);
  ctx.restore();
}

// a dot just above each loop's top, over the ink: filled if the loop reached
// the line, a ring if it fell short. the accuracy sentence says the same in
// words. drawn as part of the pad's repaint, so a theme change keeps them.
function loopMarks(ctx) {
  if (!ex.marks || !exPad.hasInk()) return;
  ctx.save();
  ctx.lineWidth = 2.5;
  for (const { x, y, reached } of ex.marks) {
    ctx.beginPath();
    ctx.arc(x, y - 14, 6, 0, 2 * Math.PI);
    ctx.fillStyle = reached ? cssVar("--accent") : cssVar("--surface");
    ctx.strokeStyle = cssVar("--accent");
    ctx.fill();
    ctx.stroke();
  }
  ctx.restore();
}

function beginDrawing() {
  exSheet.inert = false;
  exActions("draw");
  exPhase(null);
}

function scoreBigWritingTry(samples, starts, w, h, recent) {
  const geo = writingGeometry(w, h, exTarget());
  return {
    out: scoreBigWriting(samples, starts, geo, recent),
    // the writing area this try was scored in, so a saved try can be
    // re-scored when the thresholds in train.js are tuned.
    geometry: { width: w, height: h, baselineY: geo.baselineY, targetPx: geo.targetPx },
  };
}

// ---- steady tracing: watch, imagine, then trace ----

const DEMO_SECS = 4, IMAGINE_SECS = 4;
let spiralCache = null;
function spiralFor(w, h) {
  if (spiralCache?.w !== w || spiralCache?.h !== h) spiralCache = { ...tracingPath(w, h), w, h };
  return spiralCache;
}

// the whole guide while watching and imagining and after Done, so the line
// can be compared with it; the level's visibility while tracing.
function tracingGuide(ctx, w, h) {
  const path = spiralFor(w, h);
  const visibility = ex.phase === "trace" ? exTarget() : 1;
  if (visibility > 0) {
    ctx.save();
    ctx.globalAlpha = visibility;
    ctx.strokeStyle = cssVar("--guide");
    ctx.lineWidth = Math.max(2, w / 180);
    ctx.lineCap = ctx.lineJoin = "round";
    strokePath(ctx, path);
    ctx.restore();
  }
  dot(ctx, path.x[0], path.y[0], 7.5); // where to start, at every level
}

// while watching: the dot and the part of the spiral it has drawn.
function tracingOverlay(ctx, w, h) {
  if (ex.phase !== "watch" || ex.demoAt == null) return;
  const path = spiralFor(w, h);
  const along = ex.demoAt * path.length;
  ctx.save();
  ctx.strokeStyle = cssVar("--accent");
  ctx.lineWidth = Math.max(3, w / 110);
  ctx.lineCap = ctx.lineJoin = "round";
  const upTo = path.s.findIndex((s) => s > along);
  strokePath(ctx, path, upTo < 0 ? path.x.length : upTo);
  ctx.restore();
  dot(ctx, ...pointAlong(path, along), 9);
}
// watch, imagine, then trace. drawing is locked until the countdown ends
function beginTracing() {
  ex.phase = "watch";
  exSheet.inert = true;
  exActions("draw");
  $("ex-done").disabled = true;
  const imagine = () => {
    ex.phase = "imagine";
    ex.demoAt = null;
    exPad.redraw();
    let left = IMAGINE_SECS;
    const tick = () => {
      if (left === 0) {
        ex.phase = "trace";
        exPad.redraw(); // switches the guide to the level's visibility
        exSheet.inert = false;
        return exPhase(copy.TRACE_NOW);
      }
      exPhase(copy.imagine(left));
      left--;
      exAfter(1000, tick);
    };
    tick();
  };
  // reduced motion: no moving dot, just a look at the whole spiral.
  if (reduced()) {
    exPhase(copy.LOOK);
    exPad.redraw();
    return exAfter(2500, imagine);
  }
  exPhase(copy.WATCH);
  const t0 = performance.now();
  const step = (now) => {
    ex.demoAt = Math.min(1, (now - t0) / 1000 / DEMO_SECS);
    exPad.redraw();
    if (ex.demoAt < 1) exFrame = requestAnimationFrame(step);
    else exAfter(600, imagine);
  };
  exFrame = requestAnimationFrame(step);
}

// Start over while tracing clears the ink and keeps going - no second demo.
function clearTracing() {
  if (ex.phase !== "trace") return exNewTry();
  exPad.reset();
  exSheet.inert = false;
  $("ex-done").disabled = true;
  showStatus($("ex-status"), null);
}

function scoreTracingTry(samples, starts, w, h, recent) {
  const path = spiralFor(w, h);
  return {
    out: scoreTracing(samples, starts, path, recent),
    geometry: { width: w, height: h, radius: path.radius, visibility: exTarget() },
  };
}

// ---- rhythm: follow a dot that moves to a metronome ----

let waveCache = null;
function waveFor(w, h) {
  if (waveCache?.w !== w || waveCache?.h !== h) waveCache = { ...rhythmPath(w, h), w, h };
  return waveCache;
}

function rhythmGuide(ctx, w, h) {
  ctx.save();
  ctx.strokeStyle = cssVar("--guide");
  ctx.lineWidth = Math.max(2, w / 180);
  ctx.lineCap = ctx.lineJoin = "round";
  strokePath(ctx, waveFor(w, h));
  ctx.restore();
}

// the dot to follow, ringed in the surface colour so it stands out on the ink.
function rhythmOverlay(ctx) {
  if (ex.phase === "done" || !waveCache) return;
  const [x, y] = pointAlong(waveCache, (ex.dotBeat ?? 0) * waveCache.beatLength);
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, 11, 0, 2 * Math.PI);
  ctx.fillStyle = cssVar("--accent");
  ctx.strokeStyle = cssVar("--surface");
  ctx.lineWidth = 3;
  ctx.fill();
  ctx.stroke();
  ctx.restore();
}

function beginRhythm() {
  ex.phase = "ready";
  ex.dotBeat = 0;
  exSheet.inert = true;
  exActions("start");
  exPhase(copy.RHYTHM_READY);
  exPad.redraw();
}

// the metronome: one short click per beat, scheduled ahead on the audio
// clock so it stays steady. no sound (or no audio support) still leaves the dot.
let audio = null;
// each beep quickly gets louder then quieter. the higher beep means
// the countdown is over and time to follow the dot.
function click(at, accent) {
  const o = audio.createOscillator(), g = audio.createGain();
  o.frequency.value = accent ? 1320 : 880;
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(0.5, at + 0.004);
  g.gain.exponentialRampToValueAtTime(0.0001, at + 0.07);
  o.connect(g).connect(audio.destination);
  o.start(at);
  o.stop(at + 0.08);
  exClicks.push(o);
}
// counts down then moves the dot at the current level's speed
// beeps help the user keep pace with the dot
function startRhythm() {
  const beatSec = 60 / exTarget();
  const lead = 0.15; // seconds before the first click, so none is scheduled in the past
  try {
    audio ??= new (window.AudioContext || window.webkitAudioContext)();
    audio.resume(); // iOS only allows sound after a tap - this is that tap
    const t0 = audio.currentTime + lead;
    for (let k = 0; k <= COUNT_IN + RHYTHM_BEATS; k++) click(t0 + k * beatSec, k === COUNT_IN);
  } catch (err) {
    console.warn("NeuroTrace: no metronome sound", err);
  }
  ex.dotStart = performance.now() + (lead + COUNT_IN * beatSec) * 1000;
  ex.phase = "count";
  exSheet.inert = false; // the pen can wait on the dot through the count-in
  exActions("draw");
  $("ex-done").disabled = !exPad.hasInk();
  const step = (now) => {
    const t = (now - ex.dotStart) / 1000;
    if (t < 0) exPhase(copy.getReady(Math.min(COUNT_IN, Math.ceil(-t / beatSec))));
    else if (ex.phase === "count") {
      ex.phase = "run";
      exPhase(copy.FOLLOW);
    }
    ex.dotBeat = Math.min(RHYTHM_BEATS, Math.max(0, t / beatSec));
    exPad.redraw();
    if (t < RHYTHM_BEATS * beatSec) exFrame = requestAnimationFrame(step);
    else {
      ex.phase = "end";
      exPhase(copy.RHYTHM_END);
    }
  };
  exFrame = requestAnimationFrame(step);
}

function scoreRhythmTry(samples, starts, w, h, recent) {
  const beatSec = 60 / exTarget();
  const first = exPad.startedAt();
  // when the pen touched down, measured from the dot setting off.
  const penOffset = ex.dotStart != null && first != null ? (first - ex.dotStart) / 1000 : 0;
  return {
    out: scoreRhythm(samples, starts, waveFor(w, h), { beatSec, penOffset }, recent),
    geometry: { width: w, height: h, bpm: exTarget(), penOffset },
  };
}

// ---- hand skills: shrinking targets ----

const GAP_MS = 400; // between one circle disappearing and the next appearing
// a tap this far outside a circle's edge still catches it.
const TAP_SLACK = 6;
let round = null; // { results, extra, target, penSeen, inputType } for the round in progress
let tapCtx = null, tapW = 0, tapH = 0;

function sizeTapCanvas() {
  ({ ctx: tapCtx, w: tapW, h: tapH } = fitCanvas(tapCanvas));
}
new ResizeObserver(() => {
  if (tapSheet.hidden) return;
  sizeTapCanvas();
  paintTarget();
}).observe(tapCanvas);

function paintTarget(now = performance.now()) {
  if (!tapCtx) return;
  tapCtx.clearRect(0, 0, tapW, tapH);
  const t = round?.target;
  const r = t ? targetRadius(t.size, (now - t.at) / 1000) : 0;
  if (r > 0) dot(tapCtx, t.x, t.y, r);
}

function beginTargets() {
  ex.phase = "ready";
  round = null;
  exActions("start");
  exPhase(copy.TARGETS_READY);
  requestAnimationFrame(() => {
    sizeTapCanvas();
    paintTarget();
  });
}

function startTargets() {
  ex.phase = "run";
  exActions(null); // nothing to press while the circles come
  round = { results: [], extra: 0, target: null, penSeen: false, inputType: null };
  sizeTapCanvas();
  exAfter(600, nextTarget);
}

function nextTarget() {
  if (round.results.length >= TARGETS) return endRound();
  // leave room for the full circle, plus 8 pixels at the edges for error.
  const size = exTarget(), m = size / 2 + 8;
  round.target = { x: m + Math.random() * (tapW - 2 * m), y: m + Math.random() * (tapH - 2 * m), size, at: performance.now() };
  exPhase(copy.circleOf(round.results.length + 1, TARGETS));
  const step = (now) => {
    const t = round?.target;
    if (!t) return;
    if (targetRadius(t.size, (now - t.at) / 1000) <= 0) {
      round.results.push({ caught: false, ms: null }); // shrank away
      round.target = null;
      paintTarget(now);
      return exAfter(GAP_MS, nextTarget);
    }
    paintTarget(now);
    exFrame = requestAnimationFrame(step);
  };
  exFrame = requestAnimationFrame(step);
}

tapCanvas.addEventListener("pointerdown", (e) => {
  if (ex?.phase !== "run" || !round) return;
  if (e.pointerType === "pen") round.penSeen = true;
  if (e.pointerType === "touch" && round.penSeen) return; // after the first pen contact, ignore touch so a palm doesn't count
  round.inputType ??= e.pointerType === "pen" ? "pencil" : e.pointerType;
  const t = round.target;
  const rect = tapCanvas.getBoundingClientRect();
  const x = e.clientX - rect.left, y = e.clientY - rect.top;
  const r = t ? targetRadius(t.size, (e.timeStamp - t.at) / 1000) : 0;
  if (t && r > 0 && Math.hypot(x - t.x, y - t.y) <= r + TAP_SLACK) {
    round.results.push({ caught: true, ms: Math.round(e.timeStamp - t.at) });
    round.target = null;
    cancelAnimationFrame(exFrame);
    paintTarget();
    navigator.vibrate?.(10);
    exAfter(GAP_MS, nextTarget);
  } else round.extra++; // taps during the gaps count too
});

function endRound() {
  ex.phase = "done";
  exPhase(null);
  finishTry(scoreTargets(round.results, round.extra), {
    inputType: round.inputType,
    results: round.results,
    geometry: { width: tapW, height: tapH },
  });
}

// ---- every exercise ----

// how each exercise is laid out, started, scored and reported. pad: "wide",
// "square" or "tap" (the tapping area instead of the drawing pad).
const EX_UI = {
  "big-writing": {
    pad: "wide", guide: bigWritingGuide, overlay: loopMarks, begin: beginDrawing, score: scoreBigWritingTry,
    tooShort: copy.TOO_FEW_LOOPS,
    rows: ({ measures: m, vs }) => [
      ["size", copy.sizeSentence(m.size, m.shrink)],
      ["accuracy", copy.reachedLine(m.reached, m.loops, m.open, m.below)],
      ["pace", copy.paceSentence(m.pace, vs.pace)],
      ["smoothness", copy.smoothSentence(vs.smoothness)],
    ],
  },
  "steady-tracing": {
    pad: "square", guide: tracingGuide, overlay: tracingOverlay, begin: beginTracing, clear: clearTracing,
    score: scoreTracingTry, tooShort: copy.TRACE_TOO_SHORT,
    rows: ({ measures: m, vs }) => [
      ["accuracy", copy.tracingAccuracy(m.accuracy, TRACE_LIMIT)],
      ["coverage", copy.tracedShare(m.cover, "spiral")],
      ["pace", copy.paceVs(vs.pace)],
      ["smoothness", copy.smoothSentence(vs.smoothness)],
    ],
  },
  rhythm: {
    pad: "wide", guide: rhythmGuide, overlay: rhythmOverlay, begin: beginRhythm, start: startRhythm,
    score: scoreRhythmTry, tooShort: copy.RHYTHM_TOO_SHORT,
    rows: ({ measures: m, vs }) => [
      ["timing", copy.keptUp(m.lag, m.lead, RHYTHM_LAG)],
      ["coverage", copy.tracedShare(m.cover, "wave")],
      ["accuracy", copy.waveNear(m.near, RHYTHM_NEAR)],
      ["smoothness", copy.smoothSentence(vs.smoothness)],
    ],
  },
  "hand-skills": {
    pad: "tap", begin: beginTargets, start: startTargets,
    rows: ({ measures: m }) => [
      ["caught", copy.caughtSentence(m.caught, m.targets, Math.ceil(CATCH_SHARE * m.targets))],
      ["reaction", copy.reactionSentence(m.reactionMs)],
      // how many missed taps are allowed for the number of circles caught.
      // the tiny addition (1e-9) prevents floating-point rounding errors from lowering that limit.
      ["extra", copy.extraTapsSentence(m.extraTaps, Math.floor(m.caught / TAP_PRECISION - m.caught + 1e-9))],
    ],
  },
};

const exPad = createPad($("ex-pad"), {
  onInk({ cleared }) {
    $("ex-done").disabled = exSheet.inert || !exPad.hasInk();
    showStatus($("ex-status"), cleared ? copy.RESIZE_CLEARED : null);
  },
  guide: (ctx, w, h) => ex && EX_UI[ex.id].guide?.(ctx, w, h),
  overlay: (ctx, w, h) => ex && EX_UI[ex.id].overlay?.(ctx, w, h),
});

// the level, hit dots and misses-in-a-row above the exercise.
function renderExProgress() {
  const { state, levels } = ex;
  $("ex-level").textContent = copy.levelOf(state.level + 1, levels.length);
  const parts = [];
  if (state.level === levels.length - 1) parts.push(el("span", "sub", copy.TOP_LEVEL));
  else {
    const dots = el("span", "hit-dots");
    dots.setAttribute("aria-hidden", "true"); // the sentence next to it says the same
    for (let i = 0; i < HITS_TO_LEVEL_UP; i++) dots.append(el("span", i < state.hits ? "on" : null));
    parts.push(dots, el("span", "sub", copy.hitsSoFar(state.hits, HITS_TO_LEVEL_UP)));
  }
  if (state.misses) parts.push(el("span", "sub", copy.missesInARow(state.misses, MISSES_TO_LEVEL_DOWN)));
  $("ex-progress").replaceChildren(...parts);
  $("ex-too-hard").disabled = state.level === 0;
}

function exNewTry() {
  exStop();
  Object.assign(ex, { phase: null, marks: null, demoAt: null, dotBeat: null, dotStart: null });
  round = null;
  const ui = exUI();
  exSheet.hidden = ui.pad === "tap";
  tapSheet.hidden = ui.pad !== "tap";
  exSheet.classList.toggle("pad-wide", ui.pad === "wide");
  exPad.reset(); // also redraws the guide at the current level
  showStatus($("ex-status"), null);
  $("ex-result").replaceChildren();
  ui.begin();
}

function renderExResult(out, change) {
  const id = ex.id;
  const verdict = out.hit ? copy.VERDICT_HIT : out.reachedTarget ? copy.VERDICT_NOT_COUNTED[id] : copy.VERDICT_MISS;
  // reached the target but slower or shakier: say why it didn't count.
  const notes = out.reachedTarget && !out.hit
    ? [out.slower && copy.SLOWER_NOTES[id], out.shakier && copy.SHAKIER_NOTES[id]].filter(Boolean)
    : [];
  const rows = exUI().rows(out).map(([key, text]) => {
    const row = el("div", "ex-row");
    row.append(el("span", "ex-row-name", copy.MEASURE_NAMES[key]), el("span", "sub", text));
    return row;
  });
  const box = card(verdict, ...notes.map((t) => el("p", null, t)), ...rows);
  if (change) {
    const levelCopy = change === "up" ? copy.LEVEL_UP : copy.LEVEL_DOWN;
    const message = levelCopy[id](ex.state.level + 1);
    box.append(el("p", "ex-level-note", message));
  }
  $("ex-result").replaceChildren(box);
}

// a counted try (update and save progress, and show the result).
function finishTry(out, extra) {
  const before = ex.state;
  const { state, change } = applyTry(before, out, ex.levels.length);
  ex.state = state;
  setTrainingState(ex.id, state);
  saveTrainingTry({
    ts: Date.now(),
    exercise: ex.id,
    level: before.level,
    target: ex.levels[before.level],
    counted: true,
    hit: out.hit,
    reachedTarget: out.reachedTarget,
    slower: out.slower,
    shakier: out.shakier,
    measures: out.measures,
    vs: out.vs,
    ...extra,
  }).catch((err) => console.warn("NeuroTrace: couldn't save this try", err));
  renderExResult(out, change);
  renderExProgress();
  exActions("next");
  // the result is below the exercise, so scroll it into view automatically after the attempt.
  $("ex-result").scrollIntoView({ behavior: reduced() ? "auto" : "smooth", block: "nearest" });
}

onShow.exercise = (id) => {
  exStop();
  ex = { id, state: getTrainingState(id) ?? newLevelState(), levels: EXERCISES[id].levels };
  document.title = `${copy.EXERCISE_NAMES[id]} — NeuroTrace`;
  $("ex-title").textContent = copy.EXERCISE_NAMES[id];
  $("ex-instruction").textContent = copy.INSTRUCTIONS[id];
  $("ex-pad").setAttribute("aria-label", copy.PAD_LABELS[id] ?? "");
  renderExProgress();
  exNewTry();
};

$("ex-clear").addEventListener("click", () => {
  const clear = exUI().clear ?? exNewTry;
  clear();
});


$("ex-next").addEventListener("click", exNewTry);
$("ex-start").addEventListener("click", () => exUI().start());

$("ex-too-hard").addEventListener("click", () => {
  const state = tooHard(ex.state);
  if (state === ex.state) return; // already Level 1
  ex.state = state;
  setTrainingState(ex.id, state);
  renderExProgress();
  exNewTry();
  toast(copy.tooHardToast(state.level + 1));
});

$("ex-done").addEventListener("click", async () => {
  // lock the pad first so a second tap or more ink can't score this try twice.
  $("ex-done").disabled = true;
  exSheet.inert = true;
  const trace = exPad.trace();
  const starts = exPad.strokeStarts();
  const { width, height } = $("ex-pad").getBoundingClientRect();
  const tries = await listTrainingTries(ex.id).catch(() => []);
  // compare with recent tries made the same way: a mouse, a finger and a pen
  // move at very different speeds.
  const recent = tries.filter((t) => t.counted && t.inputType === trace.inputType).map((t) => t.measures);
  const { out, geometry } = exUI().score(trace.samples, starts, width, height, recent);
  if (!out.counted) {
    exSheet.inert = false; // the ink stays so they can see why, and add to it
    $("ex-done").disabled = !exPad.hasInk();
    return showStatus($("ex-status"), exUI().tooShort);
  }
  exStop(); // the rhythm dot and clicks, if still going
  ex.phase = "done";
  ex.marks = out.marks ?? null;
  exPad.redraw(); // big writing's loop dots, the whole tracing guide
  exPhase(null);
  finishTry(out, { inputType: trace.inputType, path: replayPath(trace.samples, starts), geometry });
});

// Settings > For researchers: every practice try on this device as one JSON
// file, so the thresholds in train.js can be tuned on real writing.
$("export-practice").addEventListener("click", async () => {
  const tries = await listTrainingTries().catch(() => []);
  if (!tries.length) return toast(copy.NO_PRACTICE);
  const body = { formatVersion: 1, exportedAt: new Date().toISOString(), tries };
  // replay paths are typed arrays, which JSON would turn into objects.
  const json = JSON.stringify(body, (k, v) => {
    if (!ArrayBuffer.isView(v)) return v;
    return Array.from(v, (n) => Math.round(n * 100) / 100);
  });
  const file = new File([json], `neurotrace-practice-${body.exportedAt.slice(0, 10)}.json`, { type: "application/json" });
  try {
    if (navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: file.name });
    else download(file);
  } catch (err) {
    if (err.name === "AbortError") return; // they closed the share sheet
    download(file);
  }
  toast(copy.EXPORTED);
});

// ---------- placeholders ----------
// buttons on screens that aren't built yet (the training layout) say so
// instead of doing nothing.
document.querySelectorAll("[data-soon]").forEach((btn) => btn.addEventListener("click", () => toast(copy.NOT_BUILT)));

// ---------- collection mode (handoff B2, docs/COLLECTED_FORMAT.md) ----------
// a facilitator records three spirals per participant for the device-matched
// reference. nothing is scored or shown, each session is saved on the iPad
// and only leaves it through Export.

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
    // losing a participant's spirals is the one failure that matters here,
    // so hold the session in memory and it can still be exported by hand.
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

// the share sheet where there is one (AirDrop, Files, Mail on iPad),
// otherwise a download. one session exports as an object, several as an
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

// "auto" leaves the choice to prefers-color-scheme, light/dark pin it via
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

// order matches copy.ACCENTS. styles.css holds each accent's light and dark values.
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

// every change saves right away - no Save button to forget.
// a new theme or accent spreads out from the control that was tapped.
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

// placeholder logout: back to the signed-out home. check-ins stay on the device.
$("logout").addEventListener("click", () => {
  setPrefs({ signedIn: false });
  current = null;
  location.hash = "#home";
});

// ---------- signed-out home: intro, how it works, who you're compared with ----------

$("how-steps").replaceChildren(...copy.HOW_STEPS.map((step) => el("li", null, step)));

// placeholder login until accounts exist: consent once per device, then the tabs.
$("login").addEventListener("click", () => {
  if (!getPrefs().consented) {
    location.hash = "#consent";
    return;
  }
  setPrefs({ signedIn: true });
  location.hash = "#dashboard";
});

onShow.home = async () => {
  try {
    const { reference } = await scoring;
    const all = reference.brackets.all;
    $("about-reference").textContent = copy.referenceSentence({
      referenceN: all.n, bracketKey: "all", deviceMatched: reference.deviceMatched === true,
    });
    $("about-reference").hidden = false;
  } catch {
    $("about-reference").hidden = true; // comparison information isn't available so hide it
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
// the home hero's pen dot is SMIL, which CSS can't stop - so pause it by hand.
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
