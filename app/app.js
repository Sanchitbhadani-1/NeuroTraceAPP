// App shell: a hash router over the <section class="screen"> elements in
// index.html, plus the setup screens (welcome -> consent -> about you, and
// home). Drawing, results and collection mode plug into the same router.
// Scoring lives in score.js, every sentence in copy.js, storage in store.js.

import { SPIRAL_FEATURE_ORDER, featuresFromTrace } from "./nt-features.js";
import { checkScoringFiles, scoreSession } from "./score.js";
import * as copy from "./copy.js";
import { getPrefs, setPrefs, saveAssessment } from "./store.js";
import { createPad, spiralPoints } from "./pad.js";

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

function resolve(name) {
  const prefs = getPrefs();
  const fallback = prefs.onboarded ? "home" : "welcome";
  if (!name || !document.getElementById(`screen-${name}`)) return fallback;
  if (name === "error") return loadError ? name : fallback;
  // Collection mode is run by a facilitator, not the person on the personal
  // consent flow, so it has its own gate.
  if (name.startsWith("collect")) return name === "collect" || collecting ? name : "collect";
  if (!prefs.consented && name !== "welcome" && name !== "consent") return "welcome";
  if (name === "draw" && !choice) return "about";
  if (name === "results" && !current) return "home";
  return name;
}

async function route() {
  const hash = location.hash;
  const [name, param] = hash.slice(1).split("/");
  const target = resolve(name);
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

function show(name, param) {
  for (const s of document.querySelectorAll(".screen")) s.hidden = s.id !== `screen-${name}`;
  const screen = document.getElementById(`screen-${name}`);
  document.title = `${screen.dataset.title} — NeuroTrace`;
  onShow[name]?.(param);
  scrollTo(0, 0);
  screen.querySelector("h1").focus({ preventScroll: true });
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
// One check-in is reference.trialsPerSession spirals, averaged - the user is
// measured the same way the reference group was.

const drawDone = document.getElementById("draw-done");
const drawStatus = document.getElementById("draw-status");
const drawSheet = document.getElementById("draw-pad").parentElement;
let trials = []; // this check-in's finished spirals: { trace, strokeStarts, features }
let trialsWanted = 1;

const pad = createPad(document.getElementById("draw-pad"), {
  onInk({ cleared }) {
    drawDone.disabled = drawSheet.inert || !pad.hasInk();
    showDrawStatus(cleared ? copy.RESIZE_CLEARED : null); // new ink makes an old message stale
    if (cleared) pad.showStartDot(true);
  },
});

// First sentence in bold, as in Draw.dc.html's too-short card.
function showDrawStatus(sentence) {
  drawStatus.hidden = !sentence;
  if (!sentence) return;
  const cut = sentence.indexOf(".") + 1;
  drawStatus.querySelector("strong").textContent = sentence.slice(0, cut);
  drawStatus.querySelector("strong + span").textContent = sentence.slice(cut);
}

function newTrial() {
  const n = trials.length + 1;
  document.getElementById("draw-count").textContent = `Spiral ${n} of ${trialsWanted}`;
  const progress = document.getElementById("draw-progress");
  progress.innerHTML = Array.from({ length: trialsWanted }, (_, i) => (i < n ? '<span class="on"></span>' : "<span></span>")).join("");
  progress.setAttribute("aria-valuemax", trialsWanted);
  progress.setAttribute("aria-valuenow", trials.length);
  progress.setAttribute("aria-valuetext", `${trials.length} of ${trialsWanted}`);
  pad.reset();
  pad.showStartDot(true);
  drawSheet.inert = false;
  drawDone.disabled = true;
  showDrawStatus(null);
}

onShow.draw = async () => {
  const { reference } = await scoring;
  trialsWanted = reference.trialsPerSession;
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
  if (trials.length < trialsWanted) return newTrial();

  // Scoring and saving are async: lock the pad so no new ink can reach
  // onInk and re-enable Done for a second trial or a second record.
  drawDone.disabled = true;
  drawSheet.inert = true;
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
  current = record;
  location.hash = "#results";
});

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
