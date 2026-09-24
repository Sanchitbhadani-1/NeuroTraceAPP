// App shell: a hash router over the <section class="screen"> elements in
// index.html, plus the setup screens (welcome -> consent -> about you, and
// home). Drawing, results and collection mode plug into the same router.
// Scoring lives in score.js, every sentence in copy.js, storage in store.js.

import { SPIRAL_FEATURE_ORDER } from "./nt-features.js";
import { checkScoringFiles } from "./score.js";
import * as copy from "./copy.js";
import { getPrefs, setPrefs } from "./store.js";

// ---------- spiral math, shared by the brand mark, the spiral art and the pad guide ----------

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
