// APP.JS RUNS EVERY SCREEN OF THE NEUROTRACE WEB APP
// IT SWITCHES BETWEEN SCREENS, RUNS THE SPIRAL CHECK-IN, SHOWS RESULTS AND PROGRESS, RUNS THE EXERCISES, AND HANDLES DATA COLLECTION AND SETTINGS

import { SPIRAL_FEATURE_ORDER, featuresFromTrace, normalize, preprocessTrace } from "./nt-features.js";
import { checkScoringFiles, scoreSession } from "./score.js";
import * as copy from "./copy.js";
import {
  getPrefs, setPrefs, saveAssessment, listAssessments, getAssessment, clearAssessments,
  saveCollected, listCollected, markExported, subjects, newSubjectId,
  saveTrainingTry, listTrainingTries, getTrainingState, setTrainingState,
} from "./store.js";
import {
  EXERCISES, HITS_TO_LEVEL_UP, MISSES_TO_LEVEL_DOWN, newLevelState, applyTry, tooHard, scoreBigWriting,
  pointAlong, tracingPath, scoreTracing, TRACE_LIMIT, rhythmPath, scoreRhythm, RHYTHM_BEATS, COUNT_IN, RHYTHM_LAG, RHYTHM_NEAR,
  scoreTargets, targetRadius, TARGETS, CATCH_SHARE, TAP_PRECISION,
} from "./train.js";
import { createPad, spiralPoints, cssVar } from "./pad.js";
import { reduced, applyMotion, swap, moveLens, reveal, countUp, watchTitle, toast, mountMascots, measuring } from "./motion.js";


// Find an element on the page by its id
function $(id) {
  return document.getElementById(id);
}


// Make a new element with a class name and text
function el(tag, className, text) {
  const node = document.createElement(tag);

  if (className) {
    node.className = className;
  }

  if (text != null) {
    node.textContent = text;
  }

  return node;
}


// Make a card with a title and the elements inside it
function card(title, ...children) {
  const c = el("section", "card result-card");
  c.append(el("h2", null, title), ...children);
  return c;
}


// The arrow icon on list rows and the play icon on replay buttons
const CHEVRON = '<svg class="icon chevron" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>';
const PLAY_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M7 4.5v15l13-7.5z"/></svg>';


// Make a spiral that looks hand drawn by adding a small wobble to each point
function handDrawn(r1, turns, steps) {
  const points = spiralPoints(0, r1, turns, steps);
  const wobbly = [];

  for (let i = 0; i < points.length; i++) {
    const x = points[i][0];
    const y = points[i][1];

    // Find how far along the spiral this point is and its angle
    const p = i / steps;
    const th = p * turns * 2 * Math.PI;

    // Mix three slow waves and one fast one into a wobble that starts small near the center
    const wobble = 4 * (0.6 * Math.sin(th * 0.45 + 1.3) + 0.3 * Math.sin(th * 1.3 + 2.73) + 0.1 * Math.sin(th * 3.7 + 0.91));
    const dr = (wobble + 0.4 * Math.sin(i * 2.39996)) * Math.min(1, p * 5);

    // Push the point outward or inward by the wobble
    wobbly.push([x + dr * Math.cos(th), y + dr * Math.sin(th)]);
  }

  return wobbly;
}


// Draw the logo spiral and the spiral art on the welcome screen
function drawArt() {
  const art = {
    mark: spiralPoints(0, 150, 2.25, 120),
    "art-guide": spiralPoints(0, 150, 4, 720),
    "art-trace": handDrawn(150, 4, 720),
  };

  for (const [cls, pts] of Object.entries(art)) {

    // Turn the points into an SVG path, starting with M and then a line to each point
    let d = "";
    for (let i = 0; i < pts.length; i++) {
      let command = "L";
      if (i === 0) {
        command = "M";
      }
      d += `${command}${(170 + pts[i][0]).toFixed(1)} ${(170 + pts[i][1]).toFixed(1)}`;
    }

    // Put the path on every SVG path with this class
    for (const path of document.querySelectorAll(`path.${cls}`)) {
      path.setAttribute("d", d);
    }
  }
}


// Load a JSON file, and stop with an error if it can't load
async function fetchJson(url) {
  const res = await fetch(url);

  if (!res.ok) {
    throw new Error(`couldn't load ${url} (HTTP ${res.status})`);
  }

  return res.json();
}


// Load the model and reference files, and check they match the 12 measurements
async function loadScoring() {
  const [model, reference] = await Promise.all([fetchJson("model.json"), fetchJson("reference.json")]);
  checkScoringFiles(model, reference, SPIRAL_FEATURE_ORDER);

  // Find any measurement that has no name in copy.js
  const unnamed = [];
  for (const k of SPIRAL_FEATURE_ORDER) {
    if (!copy.MEASURES[k]) {
      unnamed.push(k);
    }
  }

  if (unnamed.length) {
    throw new Error(`copy.js MEASURES has no entry for: ${unnamed.join(", ")}.`);
  }

  return { model, reference };
}


// Start loading the scoring files right away, and save the error if they fail
let loadError = null;
const scoring = loadScoring();
scoring.catch((err) => {
  loadError = err;
  console.error("NeuroTrace: scoring files failed to load - nothing will be scored", err);
});


// The age and hand picked for this check-in, the check-in being shown, and the collection session in progress
let choice = null;
let current = null;
let collecting = null;

// The screen shown before this one
let previous = null;


// Decide which screen to show, and send people to the right screen when they can't open the one asked for
function resolve(name, param) {
  const prefs = getPrefs();

  // When signed out, only the consent screen and the welcome screen can open
  if (!prefs.signedIn) {
    if (name === "consent") {
      return name;
    }
    return "home";
  }

  // An empty or unknown screen name goes to the dashboard
  if (!name || name === "home" || !$(`screen-${name}`)) {
    return "dashboard";
  }

  // The error screen only opens when the scoring files failed to load
  if (name === "error") {
    if (loadError) {
      return name;
    }
    return "dashboard";
  }

  // The collection screens after the first one only open during a session
  if (name.startsWith("collect")) {
    if (name === "collect" || collecting) {
      return name;
    }
    return "collect";
  }

  // Everything else needs consent first
  if (!prefs.consented && name !== "consent") {
    return "consent";
  }

  // The drawing screen needs an age and hand first
  if (name === "draw" && !choice) {
    return "about";
  }

  // An exercise that isn't built yet goes back to the training screen
  if (name === "exercise" && !EXERCISES[param]?.built) {
    return "training";
  }

  // The results screen needs a check-in to show
  if (name === "results" && !current && !param) {
    return "dashboard";
  }

  return name;
}


// Show the screen named in the address bar after the #
async function route() {
  const hash = location.hash;
  const [name, param] = hash.slice(1).split("/");

  // If this screen can't open, go to the right one
  const target = resolve(name, param);
  if (target !== name) {
    location.replace(`#${target}`);
    return;
  }

  // Wait for the scoring files on these screens
  if (name === "draw" || name === "results" || name === "progress") {
    try {
      await scoring;
    } catch {
      location.replace("#error");
      return;
    }

    // Stop if the person moved to another screen while waiting
    if (location.hash !== hash) {
      return;
    }
  }

  show(name, param);
}


// The setup step for each screen, the tabs in order, and the screens whose title shows in the top bar
const onShow = {};
const TAB_ORDER = ["dashboard", "testing", "training", "progress", "settings"];
const TABS = new Set(TAB_ORDER);
const TITLED = new Set([...TAB_ORDER, "results"]);


// Switch screens with a slide between tabs, or a fade for every other change
function show(name, param) {
  const from = TAB_ORDER.indexOf(previous);
  const to = TAB_ORDER.indexOf(name);

  // Slide left when moving to a tab further right, slide right when moving back, and fade otherwise
  let kind = "fade";
  if (from >= 0 && to >= 0 && from !== to) {
    if (to > from) {
      kind = "left";
    } else {
      kind = "right";
    }
  }

  swap(() => showNow(name, param), { kind });
}


// Show one screen and hide the others
function showNow(name, param) {

  // Hide every screen except this one
  for (const s of document.querySelectorAll(".screen")) {
    s.hidden = s.id !== `screen-${name}`;
  }

  // Set the page title and run the screen's setup step
  const screen = $(`screen-${name}`);
  document.title = `${screen.dataset.title} — NeuroTrace`;
  onShow[name]?.(param);

  // Scroll to the top and move the focus to the screen's heading
  scrollTo(0, 0);
  screen.querySelector("h1").focus({ preventScroll: true });

  // Show the tab bar only on the tab screens, and mark the current tab
  const tabbar = $("tabbar");
  tabbar.hidden = !TABS.has(name);
  for (const a of tabbar.querySelectorAll("a")) {
    if (a.dataset.tab === name) {
      a.setAttribute("aria-current", "page");
    } else {
      a.removeAttribute("aria-current");
    }
  }
  moveLens(tabbar);

  // Show the screen's title in the top bar on the titled screens
  if (TITLED.has(name)) {
    watchTitle(screen.querySelector("h1"));
  } else {
    watchTitle(null);
  }

  previous = name;
}


// THE CONSENT SCREEN

const consentBoxes = document.querySelectorAll('#screen-consent input[name="consent"]');
const consentContinue = $("consent-continue");
const consentHelp = $("consent-help");


// Turn on the Continue button only when every box is checked
function syncConsent() {
  let ready = true;
  for (const box of consentBoxes) {
    if (!box.checked) {
      ready = false;
      break;
    }
  }

  consentContinue.disabled = !ready;
  consentHelp.hidden = ready;
}


// Check the boxes if the person already agreed
onShow.consent = () => {
  const { consented } = getPrefs();
  for (const box of consentBoxes) {
    box.checked = consented;
  }
  syncConsent();
};

$("screen-consent").addEventListener("change", syncConsent);

// Save the consent and go to the dashboard
consentContinue.addEventListener("click", () => {
  setPrefs({ consented: true, onboarded: true, signedIn: true });
  location.hash = "#dashboard";
});


// THE ABOUT YOU SCREEN, WHERE THE PERSON PICKS THEIR AGE AND HAND

const aboutContinue = $("about-continue");


// Find which option is picked in a group of choices
function checkedValue(name) {
  return document.querySelector(`#screen-about input[name="${name}"]:checked`)?.value;
}


// Turn on the Continue button only when an age and a hand are both picked
function syncAbout() {
  aboutContinue.disabled = !(checkedValue("age") && checkedValue("hand"));
}


// Make the age choices as a row of chips
function ageChips(name) {
  let html = "";
  for (const { label } of copy.AGE_CHOICES) {
    html += `<label class="chip"><input type="radio" name="${name}" value="${label}"><span>${label}</span></label>`;
  }
  return html;
}

$("age-choices").innerHTML = ageChips("age");


// Pick the saved age and hand, and set the back button to the screen the person came from
onShow.about = () => {
  const { ageChoice, hand } = getPrefs();

  for (const r of document.querySelectorAll('#screen-about input[name="age"]')) {
    r.checked = r.value === ageChoice;
  }

  for (const r of document.querySelectorAll('#screen-about input[name="hand"]')) {
    r.checked = r.value === hand;
  }

  syncAbout();

  if (TABS.has(previous)) {
    $("about-back").href = `#${previous}`;
  } else {
    $("about-back").href = "#testing";
  }
};

$("screen-about").addEventListener("change", syncAbout);

// Save the age and hand, find the age group, and go to the drawing screen
aboutContinue.addEventListener("click", () => {
  const ageChoice = checkedValue("age");
  const hand = checkedValue("hand");
  setPrefs({ ageChoice, hand });

  const picked = copy.AGE_CHOICES.find((c) => c.label === ageChoice);
  choice = { ageChoice, bracket: picked.bracket, hand };
  location.hash = "#draw";
});


// THE SPIRAL CHECK-IN

// Each check-in has 3 spirals
const CHECKIN_TRIALS = 3;

const drawDone = $("draw-done");
const drawStatus = $("draw-status");
const drawSheet = $("draw-pad").parentElement;
let trials = [];


// The drawing pad, which turns on the Done button once there's ink
const pad = createPad($("draw-pad"), {
  onInk({ cleared }) {
    drawDone.disabled = drawSheet.inert || !pad.hasInk();

    // If the pad was cleared from the screen changing size, say so and show the start dot again
    if (cleared) {
      showStatus(drawStatus, copy.RESIZE_CLEARED);
      pad.showStartDot(true);
    } else {
      showStatus(drawStatus, null);
    }
  },
});


// Show a message box with its first sentence in bold, or hide it when there's no message
function showStatus(box, sentence) {
  box.hidden = !sentence;
  if (!sentence) {
    return;
  }

  // Restart the shake animation
  box.classList.remove("shake");
  void box.offsetWidth;
  box.classList.add("shake");

  // Split the message after its first period
  const cut = sentence.indexOf(".") + 1;
  box.querySelector("strong").textContent = sentence.slice(0, cut);
  box.querySelector("strong + span").textContent = sentence.slice(cut);
}


// Show one dot per spiral, filled in for the ones done and the one being drawn
function progressDots(progress, done, total) {
  let html = "";
  for (let i = 0; i < total; i++) {
    if (i < done) {
      html += '<span class="on"></span>';
    } else if (i === done) {
      html += '<span class="on now"></span>';
    } else {
      html += "<span></span>";
    }
  }
  progress.innerHTML = html;

  // Tell screen readers how many are done
  progress.setAttribute("aria-valuemax", total);
  progress.setAttribute("aria-valuenow", done);
  progress.setAttribute("aria-valuetext", `${done} of ${total}`);
}


// Clear the pad for the next spiral
function newTrial() {
  $("draw-count").textContent = `Spiral ${trials.length + 1} of ${CHECKIN_TRIALS}`;
  progressDots($("draw-progress"), trials.length, CHECKIN_TRIALS);
  pad.reset();
  pad.showStartDot(true);
  drawSheet.inert = false;
  drawDone.disabled = true;
  showStatus(drawStatus, null);
}


// Start a new check-in with no spirals
onShow.draw = () => {
  trials = [];
  newTrial();
};

$("draw-restart").addEventListener("click", newTrial);


// Save each spiral, and after the third one score the check-in and show the results
drawDone.addEventListener("click", async () => {
  const trace = pad.trace(choice.hand);

  // Turn the spiral into its 12 measurements, or ask for a longer drawing
  let features;
  try {
    features = featuresFromTrace(trace);
  } catch {
    showStatus(drawStatus, copy.TOO_SHORT);
    return;
  }

  trials.push({ trace, strokeStarts: pad.strokeStarts(), features });
  navigator.vibrate?.(12);

  // Before the third spiral, show a saved message and clear the pad for the next one
  if (trials.length < CHECKIN_TRIALS) {
    toast(copy.SPIRAL_SAVED(trials.length));
    drawSheet.classList.add("wipe");
    if (reduced()) {
      setTimeout(newTrial, 0);
    } else {
      setTimeout(newTrial, 160);
    }
    return;
  }

  // Lock the pad and show the measuring screen
  drawDone.disabled = true;
  drawSheet.inert = true;
  const finish = measuring();

  // Score the three spirals together
  const { model, reference } = await scoring;
  const allFeatures = [];
  for (const t of trials) {
    allFeatures.push(t.features);
  }
  const result = scoreSession(allFeatures, model, reference, choice.bracket);

  // Save each spiral's points, measurements and a small copy for replay
  const savedTrials = [];
  for (const { trace, strokeStarts, features } of trials) {
    savedTrials.push({
      samples: trace.samples, strokeStarts, features, path: replayPath(trace.samples, strokeStarts),
    });
  }

  // Build the check-in record
  const record = {
    ts: Date.now(),
    task: "spiral",
    hand: choice.hand,
    ageChoice: choice.ageChoice,
    bracketChoice: choice.bracket,
    inputType: trials[0].trace.inputType,
    deviceLabel: trials[0].trace.deviceLabel,
    trials: savedTrials,
    features: result.features,
    result,
  };

  // Save it to the history
  try {
    await saveAssessment(record);
  } catch (err) {
    console.warn("NeuroTrace: couldn't save this check-in to history", err);
  }

  // Wait for the measuring screen to finish, then show the results
  const hide = await finish();
  current = record;
  location.hash = "#results";
  hide?.();
});

drawSheet.addEventListener("animationend", () => {
  drawSheet.classList.remove("wipe");
});


// A small dot that follows the pen tip on the pad
const penTip = el("span", "pen-tip");
drawSheet.append(penTip);
const canvasEl = $("draw-pad");


// Move the dot to where the pen is
function movePenTip(e) {
  const r = canvasEl.getBoundingClientRect();
  penTip.style.transform = `translate(${e.clientX - r.left}px, ${e.clientY - r.top}px)`;
}


// Show the dot when the pen touches down, and hide it when the pen lifts or leaves
canvasEl.addEventListener("pointerdown", (e) => {
  movePenTip(e);
  penTip.classList.add("on");
});
canvasEl.addEventListener("pointermove", movePenTip);
for (const type of ["pointerup", "pointercancel", "pointerleave"]) {
  canvasEl.addEventListener(type, () => {
    penTip.classList.remove("on");
  });
}


// THE RESULTS SCREEN
// The result score itself is never shown, only the result level and each measurement's place

// Show dates with the day, month and time
const whenFmt = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });


// One measurement's row, with its name, its sentence, and a dot on a track
function measureRow(key, frac) {
  const row = el("div", "measure");

  // Put the dot at the measurement's place from 0% to 100%
  const track = el("div", "track");
  track.setAttribute("aria-hidden", "true");
  const dot = el("span", "track-dot");
  dot.style.setProperty("--p", `${Math.round(frac * 100)}%`);
  track.append(dot);

  // Split the sentence around its number
  const match = copy.measureSentence(key, frac).match(/^(.*?)(\d+)(%.*)$/);
  const lead = match[1];
  const n = match[2];
  const tail = match[3];
  const sentence = el("span", "sub");
  const num = el("span", "num", n);
  sentence.append(lead, num, tail);

  row.dataset.n = n;
  row.append(el("span", "measure-name", copy.MEASURES[key].name), sentence, track);
  return row;
}


// The three result levels as bars, with the person's level lit up
function levels(tier) {
  const wrap = el("div", "levels");
  wrap.setAttribute("role", "img");
  wrap.setAttribute("aria-label", `Result level: ${copy.TIER_SHORT[tier]}, ${tier + 1} of 3`);

  for (let i = 0; i < copy.TIER_SHORT.length; i++) {
    let className = "level";
    if (i === tier) {
      className = "level on";
    }

    const step = el("span", className);
    step.append(el("span", "level-bar"), el("span", "level-label", copy.TIER_SHORT[i]));
    wrap.append(step);
  }

  return wrap;
}


// The drawing being shown on the results screen
let drawing = null;


// Build the whole results screen for one check-in
function renderResults(rec) {
  const { result } = rec;
  const tier = copy.TIERS[result.tier];
  $("results-meta").textContent = `Spiral check-in · ${whenFmt.format(rec.ts)}`;
  $("results-title").textContent = tier.label;

  // A measurement is shown only if it has a place in the result
  const shown = (key) => key in result.measurePct;

  // The card with the measurements that stood out the most
  const stoodOutRows = [];
  for (const k of result.topSignals) {
    if (shown(k)) {
      stoodOutRows.push(measureRow(k, result.measurePct[k]));
    }
  }
  const stoodOut = card("What stood out", el("p", "sub", copy.STOOD_OUT_CAPTION), ...stoodOutRows);

  // The card with every measurement, with labels for the low, middle and high ends of the track
  const every = card("Every measure", el("p", "sub", copy.EVERY_MEASURE_CAPTION));
  const scale = el("div", "scale-labels");
  scale.setAttribute("aria-hidden", "true");
  scale.append(el("span", null, "Lowest"), el("span", null, "Halfway"), el("span", null, "Highest"));
  every.append(scale);

  // Add the measurements one group at a time
  for (const g of copy.GROUPS) {

    // Find the measurements in this group
    const keys = [];
    for (const k of SPIRAL_FEATURE_ORDER) {
      if (copy.MEASURES[k].group === g.id && shown(k)) {
        keys.push(k);
      }
    }

    // Skip groups with no measurements
    if (!keys.length) {
      continue;
    }

    const rows = [];
    for (const k of keys) {
      rows.push(measureRow(k, result.measurePct[k]));
    }

    const group = el("div", "measure-group");
    group.append(el("h3", null, g.title), el("p", "sub", g.desc), ...rows);
    every.append(group);
  }

  // The paragraphs of the What this means card
  const meaning = [];
  for (const p of tier.meaning) {
    meaning.push(el("p", null, p));
  }

  // Every part of the screen in the order it's read
  const parts = [
    el("p", "summary", copy.RESULT_SUMMARY),
    levels(result.tier),
    el("p", "sub reference", copy.referenceSentence(result)),
    card("What this means", ...meaning),
    stoodOut,
    card("What you can do", el("p", null, tier.todo)),
    drawingCard(rec),
    every,
  ];

  // Keep that reading order when the screen is in one column
  for (let i = 0; i < parts.length; i++) {
    parts[i].style.order = i;
  }

  // On wide screens the two measurement cards go in a second column
  const main = el("div", "results-main");
  const side = el("div", "results-side");
  for (const n of parts) {
    if (n !== stoodOut && n !== every) {
      main.append(n);
    }
  }
  side.append(stoodOut, every);
  $("results-body").replaceChildren(main, side);

  // Fade the parts in as they scroll into view, and count each number up
  reveal(parts);
  reveal($("results-body").querySelectorAll(".measure"), (row) => countUp(row.querySelector(".num"), Number(row.dataset.n)));
}


// The card with the person's drawing, a replay button and a speed chart
function drawingCard(rec) {

  // Find the spirals that still have their points saved
  const drawn = [];
  for (const t of rec.trials ?? []) {
    if (t.samples) {
      drawn.push(t);
    }
  }
  const trial = drawn[0];
  drawing = null;

  // If no points are saved, say the drawing was removed
  if (!trial?.samples) {
    return card("Your drawing", el("p", "sub", copy.DRAWING_PRUNED));
  }

  // The canvas for the drawing
  const canvas = el("canvas", "drawing");
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", "Your recorded line drawn under the smoothed version the measures are taken from");

  // The key for the two lines
  const legend = el("div", "legend");
  for (const [cls, text] of [["swatch-raw", copy.RAW_LEGEND], ["swatch-filtered", copy.FILTERED_LEGEND]]) {
    const row = el("div", "legend-row");
    row.append(el("span", `swatch ${cls}`), el("span", null, text));
    legend.append(row);
  }

  // The replay button and the speed chart
  const replay = el("button", "btn btn-secondary btn-compact");
  replay.type = "button";
  replay.innerHTML = PLAY_ICON + "Replay drawing";
  const speed = el("canvas", "speed");
  speed.setAttribute("role", "img");
  speed.setAttribute("aria-label", "Drawing speed over time");

  // Get the drawing ready to show, or say it was removed if that fails
  let prepared;
  try {
    prepared = prepareDrawing(trial);
  } catch (err) {
    console.warn("NeuroTrace: couldn't prepare the drawing", err);
    return card("Your drawing", el("p", "sub", copy.DRAWING_PRUNED));
  }

  drawing = { canvas, speed, prepared };
  replay.addEventListener("click", () => {
    replayDrawing(drawing);
  });
  requestAnimationFrame(() => {
    paintDrawing(drawing);
  });

  // With more than one spiral, add buttons to pick which one to show
  let picker = "";
  if (drawn.length > 1) {
    picker = el("div", "segmented");
    picker.setAttribute("role", "radiogroup");
    picker.setAttribute("aria-label", "Which spiral to show");
    picker.style.gridTemplateColumns = `repeat(${drawn.length}, minmax(0, 1fr))`;
    picker.style.setProperty("--n", drawn.length);

    // One button per spiral, with the first one picked
    for (let i = 0; i < drawn.length; i++) {
      let checked = "";
      if (i === 0) {
        checked = " checked";
      }
      picker.insertAdjacentHTML("beforeend",
        `<label class="segment"><input type="radio" name="which-spiral" value="${i}"${checked}><span>Spiral ${i + 1}</span></label>`);
    }

    // Show the spiral that was picked
    picker.addEventListener("change", ({ target }) => {
      try {
        drawing.prepared = prepareDrawing(drawn[Number(target.value)]);
      } catch (err) {
        console.warn("NeuroTrace: couldn't prepare that spiral", err);
        return;
      }
      cancelAnimationFrame(drawing.frame);
      paintDrawing(drawing);
    });
  }

  return card("Your drawing", picker, canvas, legend, replay, el("hr"),
    el("h3", null, "Speed along the line"), el("p", "sub", copy.SPEED_CAPTION), speed);
}


// Find the box around one or more lines
function bounds(...lines) {
  const box = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity };

  for (const [x, y] of lines) {
    for (let i = 0; i < x.length; i++) {
      if (x[i] < box.minX) {
        box.minX = x[i];
      }
      if (x[i] > box.maxX) {
        box.maxX = x[i];
      }
      if (y[i] < box.minY) {
        box.minY = y[i];
      }
      if (y[i] > box.maxY) {
        box.maxY = y[i];
      }
    }
  }

  return box;
}


// Get a spiral ready to show, with the drawn line, the smoothed line and the speed between points
function prepareDrawing({ samples, strokeStarts }) {

  // Copy the times and positions into number arrays
  const t = new Float64Array(samples.length);
  const x = new Float64Array(samples.length);
  const y = new Float64Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    t[i] = samples[i].t;
    x[i] = samples[i].x;
    y[i] = samples[i].y;
  }

  // The drawn line centered and scaled, and the smoothed line the measurements use
  const raw = normalize(x, y);
  const filtered = preprocessTrace(t, x, y).slice(1);
  const starts = new Set(strokeStarts ?? [0]);

  // Find the speed between each pair of points, skipping the jump at each pen lift
  const speeds = [];
  for (let i = 1; i < samples.length; i++) {
    const dt = samples[i].t - samples[i - 1].t;

    if (starts.has(i) || dt <= 0) {
      continue;
    }

    speeds.push(Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y) / dt);
  }

  return { t, raw, filtered, starts, speeds, box: bounds(raw, filtered) };
}


// Size a canvas to its space on the screen, sharp on high resolution screens
function fitCanvas(canvas) {
  const dpr = window.devicePixelRatio || 1;
  const { width, height } = canvas.getBoundingClientRect();
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);

  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { ctx, w: width, h: height };
}


// Draw a line through the first n points, starting a new line at each pen lift
function strokeLine(ctx, [px, py], map, n, starts, style, width) {
  ctx.save();
  ctx.strokeStyle = style;
  ctx.lineWidth = width;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.beginPath();

  for (let i = 0; i < n; i++) {
    const [X, Y] = map(px[i], py[i]);
    if (i === 0 || starts?.has(i)) {
      ctx.moveTo(X, Y);
    } else {
      ctx.lineTo(X, Y);
    }
  }

  ctx.stroke();
  ctx.restore();
}


// Draw the spiral on the results card, up to upTo seconds when replaying
function paintDrawing(d, upTo = Infinity) {
  if (!d?.canvas.isConnected) {
    return;
  }

  const { ctx, w, h } = fitCanvas(d.canvas);
  const { raw, filtered, t, starts, box } = d.prepared;

  // Scale the drawing to fit inside the canvas with a 16 point border, keeping its shape
  const pad = 16;
  const s = Math.min((w - 2 * pad) / (box.maxX - box.minX || 1), (h - 2 * pad) / (box.maxY - box.minY || 1));
  const ox = w / 2 - s * (box.minX + box.maxX) / 2;
  const oy = h / 2 - s * (box.minY + box.maxY) / 2;
  const map = (x, y) => [ox + s * x, oy + s * y];

  // Count the points drawn by upTo seconds
  let n = raw[0].length;
  if (upTo < Infinity) {
    n = 0;
    while (n < t.length && t[n] <= upTo) {
      n++;
    }
  }

  // Draw the line the person drew, faded
  ctx.globalAlpha = 0.55;
  strokeLine(ctx, raw, map, n, starts, cssVar("--ink2"), 1.5);
  ctx.globalAlpha = 1;

  // Once the whole drawing is shown, draw the smoothed line on top
  if (n === raw[0].length) {
    strokeLine(ctx, filtered, map, filtered[0].length, null, cssVar("--accent"), 3);
  }

  // Draw the speed chart when not replaying
  if (upTo === Infinity) {
    paintSpeed(d);
  }
}


// Draw the speed chart as a filled area with a line on top
function paintSpeed({ speed, prepared: { speeds } }) {
  const { ctx, w, h } = fitCanvas(speed);
  if (speeds.length < 2) {
    return;
  }

  // Find the top speed, at least 1
  let top = 1;
  for (const v of speeds) {
    if (v > top) {
      top = v;
    }
  }

  // Turn a point's number into its place across, and a speed into its height
  const X = (i) => (i / (speeds.length - 1)) * w;
  const Y = (v) => h - 4 - (v / top) * (h - 8);

  // Fill the area under the speed line
  ctx.beginPath();
  ctx.moveTo(0, h);
  for (let i = 0; i < speeds.length; i++) {
    ctx.lineTo(X(i), Y(speeds[i]));
  }
  ctx.lineTo(w, h);
  ctx.closePath();
  ctx.fillStyle = cssVar("--accent-soft");
  ctx.fill();

  // Draw the speed line on top
  ctx.beginPath();
  for (let i = 0; i < speeds.length; i++) {
    if (i === 0) {
      ctx.moveTo(X(i), Y(speeds[i]));
    } else {
      ctx.lineTo(X(i), Y(speeds[i]));
    }
  }
  ctx.strokeStyle = cssVar("--accent");
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  ctx.stroke();
}


// Replay the drawing at the speed it was drawn
function replayDrawing(d) {
  cancelAnimationFrame(d.frame);
  const end = d.prepared.t[d.prepared.t.length - 1];
  const start = performance.now();

  // Each frame, draw the spiral up to the time passed so far
  const step = (now) => {
    const elapsed = (now - start) / 1000;

    if (elapsed >= end) {
      paintDrawing(d, Infinity);
    } else {
      paintDrawing(d, elapsed);
    }

    if (elapsed < end) {
      d.frame = requestAnimationFrame(step);
    }
  };

  d.frame = requestAnimationFrame(step);
}


// Draw the spiral again when the screen switches between light and dark mode
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  paintDrawing(drawing);
});


// Show the check-in that was just done, or one from the history by its id
onShow.results = async (id) => {
  if (id) {
    const rec = await getAssessment(Number(id)).catch(() => null);

    if (!rec?.result) {
      location.replace("#dashboard");
      return;
    }

    current = rec;
  }

  renderResults(current);
  $("results-title").focus({ preventScroll: true });
};


// THE DASHBOARD

// Show a check-in's date as Today, Yesterday, or the day and date
function historyWhen(ts) {
  const d = new Date(ts);
  const today = new Date();
  const time = d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });

  // Count the days between the check-in and today
  const days = Math.round((new Date(today.toDateString()) - new Date(d.toDateString())) / 864e5);

  if (days === 0) {
    return `Today, ${time}`;
  }
  if (days === 1) {
    return `Yesterday, ${time}`;
  }
  return `${d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "short" })}, ${time}`;
}

const historyEmpty = document.querySelector("#history .empty");


// List every past check-in, newest first, or show the empty message
onShow.dashboard = async () => {
  const records = await listAssessments().catch((err) => {
    console.warn("NeuroTrace: couldn't read history", err);
    return [];
  });

  if (!records.length) {
    $("history").replaceChildren(historyEmpty);
    return;
  }

  // One row per check-in with its date and result, linking to its results
  const list = el("div", "card history-list");
  for (const rec of records) {
    const row = el("a", "history-row");
    row.href = `#results/${rec.id}`;

    const text = el("span", "history-text");
    text.append(el("span", "history-when", historyWhen(rec.ts)), el("span", "sub", copy.TIERS[rec.result.tier].label));
    row.append(text);
    row.insertAdjacentHTML("beforeend", CHEVRON);
    list.append(row);
  }

  $("history").replaceChildren(list);
};


// THE PROGRESS SCREEN, COMPARING THE FIRST AND LATEST CHECK-IN

// Check whether two check-ins used the same hand and the same input, Pencil or finger
function sameSetup(a, b) {
  return a.hand === b.hand && a.inputType === b.inputType;
}


// One measurement's row with the first and latest place, as sentences and as two dots on a track
function compareRow(key, first, latest) {
  const row = el("div", "measure");

  // Hide the track from screen readers
  const track = el("div", "track");
  track.setAttribute("aria-hidden", "true");
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


// Keep up to 60 points per second in the replay copy
const REPLAY_HZ = 60;


// Make a small copy of the drawing for replay, saved with each check-in
// It keeps points at least 1/60 of a second apart, plus the first and last point of each stroke
function replayPath(samples, strokeStarts = [0]) {
  const starts = new Set(strokeStarts);

  // Pick which points to keep
  const keep = [];
  let last = -Infinity;
  for (let i = 0; i < samples.length; i++) {
    const s = samples[i];
    const edge = starts.has(i) || starts.has(i + 1) || i === samples.length - 1;

    if (edge || s.t - last >= 1 / REPLAY_HZ) {
      keep.push(i);
      last = s.t;
    }
  }

  // Copy the kept times and positions into smaller number arrays
  const t = new Float32Array(keep.length);
  const x = new Float32Array(keep.length);
  const y = new Float32Array(keep.length);
  for (let j = 0; j < keep.length; j++) {
    t[j] = samples[keep[j]].t;
    x[j] = samples[keep[j]].x;
    y[j] = samples[keep[j]].y;
  }

  // Find where each stroke starts in the kept points
  const keptStarts = [];
  for (let j = 0; j < keep.length; j++) {
    if (starts.has(keep[j])) {
      keptStarts.push(j);
    }
  }

  return { t, x, y, starts: keptStarts };
}


// The saved replay copy, or one made from the raw points for older check-ins, or null when there's neither
function checkinPath(rec) {
  const trial = (rec.trials ?? []).find((t) => t.path || t.samples);

  if (!trial) {
    return null;
  }

  return trial.path ?? replayPath(trial.samples, trial.strokeStarts);
}


// A card with a check-in's date, result and drawing
// live is the canvas and drawing for replay, or null when there's no drawing
function snapshot(label, rec, result) {
  const box = el("section", "card snapshot");
  box.append(
    el("span", "sub", label),
    el("h2", "card-title", whenFmt.format(rec.ts)),
    el("p", null, copy.TIERS[result.tier].label),
  );

  // If there's no drawing, say so
  const path = checkinPath(rec);
  if (!path?.t.length) {
    box.append(el("p", "sub", copy.REPLAY_MISSING));
    return { box, live: null };
  }

  // Add a canvas for the drawing and how long it took
  const canvas = el("canvas", "thumb");
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", `Your spiral from ${whenFmt.format(rec.ts)}`);
  box.append(canvas, el("p", "sub", copy.drawnIn(path.t[path.t.length - 1])));
  return { box, live: { canvas, path } };
}


// Draw a saved drawing fitted to its canvas, up to upTo seconds, with a dot at the pen tip while replaying
function paintPath({ canvas, path }, upTo = Infinity) {
  if (!canvas.isConnected) {
    return;
  }

  const { ctx, w, h } = fitCanvas(canvas);
  if (!w) {
    return;
  }

  // Scale the drawing to fit with a 10 point border, keeping its shape, and using 1 for a flat drawing
  const { t, x, y, starts } = path;
  const { minX, maxX, minY, maxY } = bounds([x, y]);
  const pad = 10;
  const spanX = maxX - minX || 1;
  const spanY = maxY - minY || 1;
  const s = Math.min((w - 2 * pad) / spanX, (h - 2 * pad) / spanY);
  const ox = w / 2 - s * (minX + maxX) / 2;
  const oy = h / 2 - s * (minY + maxY) / 2;
  const lifts = new Set(starts);

  // Count the points drawn by upTo seconds
  let n = 0;
  while (n < t.length && t[n] <= upTo) {
    n++;
  }

  // Draw the line, starting a new line at each pen lift
  const accent = cssVar("--accent");
  ctx.strokeStyle = accent;
  ctx.fillStyle = accent;
  ctx.lineWidth = 2;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const X = ox + s * x[i];
    const Y = oy + s * y[i];
    if (i === 0 || lifts.has(i)) {
      ctx.moveTo(X, Y);
    } else {
      ctx.lineTo(X, Y);
    }
  }
  ctx.stroke();

  // While replaying, draw a dot at the pen tip
  if (n > 0 && n < t.length) {
    ctx.beginPath();
    ctx.arc(ox + s * x[n - 1], oy + s * y[n - 1], 4, 0, 2 * Math.PI);
    ctx.fill();
  }
}

let progressFrame = 0;


// Replay every drawing at once, each at its own speed
function replayAll(lives) {
  cancelAnimationFrame(progressFrame);

  // Find when the longest drawing ends
  let end = 0;
  for (const l of lives) {
    end = Math.max(end, l.path.t[l.path.t.length - 1]);
  }

  const start = performance.now();

  // Each frame, draw every drawing up to the time passed so far
  const step = (now) => {
    const elapsed = (now - start) / 1000;

    for (const l of lives) {
      paintPath(l, elapsed);
    }

    // Keep going until the longest drawing ends, while at least one canvas is still on screen
    let anyShown = false;
    for (const l of lives) {
      if (l.canvas.isConnected) {
        anyShown = true;
        break;
      }
    }

    if (elapsed < end && anyShown) {
      progressFrame = requestAnimationFrame(step);
    }
  };

  progressFrame = requestAnimationFrame(step);
}


// Compare the first and latest check-in with the same hand and input, measurement by measurement
onShow.progress = async () => {
  const body = $("progress-body");
  const records = await listAssessments().catch(() => []);
  const latest = records[0];

  // Find the earliest check-in with the same setup, records come newest first
  let first = null;
  if (latest) {
    for (const r of records) {
      if (sameSetup(r, latest)) {
        first = r;
      }
    }
  }

  // With fewer than two check-ins, show the empty message
  if (!first || first === latest) {
    const empty = el("div", "card empty");
    const mascot = el("span", "empty-mascot");
    mascot.dataset.mascot = "idle";
    empty.append(mascot, el("p", null, copy.PROGRESS_EMPTY));
    mountMascots(empty);
    body.replaceChildren(empty);
    return;
  }

  // Score both check-ins again with today's reference and the latest check-in's age group
  const { model, reference } = await scoring;
  const place = (rec) => scoreSession([rec.features ?? rec.result.features], model, reference, latest.bracketChoice);
  const a = place(first);
  const b = place(latest);

  // The two cards side by side
  const one = snapshot("First check-in", first, a);
  const two = snapshot("Latest check-in", latest, b);
  const pair = el("div", "snapshot-pair");
  pair.append(one.box, two.box);

  // The drawings that can be replayed
  const lives = [];
  for (const live of [one.live, two.live]) {
    if (live) {
      lives.push(live);
    }
  }

  // The replay button
  const replay = el("button", "btn btn-secondary btn-compact replay-both");
  replay.type = "button";
  if (lives.length > 1) {
    replay.innerHTML = PLAY_ICON + "Replay both";
  } else {
    replay.innerHTML = PLAY_ICON + "Replay drawing";
  }
  replay.addEventListener("click", () => {
    replayAll(lives);
  });

  // The key for the first and latest dots
  const key = el("div", "dot-legend");
  key.setAttribute("aria-hidden", "true");
  for (const [cls, text] of [["legend-key then", "First"], ["legend-key", "Latest"]]) {
    const item = el("span");
    item.append(el("span", cls), text);
    key.append(item);
  }

  // The card with every measurement, one group at a time
  const measures = card("Measure by measure", el("p", "sub", copy.PROGRESS_CAPTION), key);
  const shown = (k) => k in a.measurePct && k in b.measurePct;
  for (const g of copy.GROUPS) {

    // Find the measurements in this group
    const keys = [];
    for (const k of SPIRAL_FEATURE_ORDER) {
      if (copy.MEASURES[k].group === g.id && shown(k)) {
        keys.push(k);
      }
    }

    // Skip groups with no measurements
    if (!keys.length) {
      continue;
    }

    const rows = [];
    for (const k of keys) {
      rows.push(compareRow(k, a.measurePct[k], b.measurePct[k]));
    }

    const group = el("div", "measure-group");
    group.append(el("h3", null, g.title), ...rows);
    measures.append(group);
  }

  // Put the screen together
  const meta = el("p", "sub progress-meta", copy.progressSetup(latest.hand, latest.inputType));
  const parts = [meta, pair];
  if (lives.length) {
    parts.push(replay);
  }
  parts.push(measures);
  body.replaceChildren(...parts);

  // Replay the drawings once when the screen opens, or show them finished with Reduced Motion on
  requestAnimationFrame(() => {
    if (reduced()) {
      for (const l of lives) {
        paintPath(l);
      }
    } else {
      replayAll(lives);
    }
  });
};


// THE TRAINING SCREEN

// Show each exercise's saved level and last change, or Coming soon
onShow.training = () => {
  for (const btn of document.querySelectorAll("#screen-training [data-exercise]")) {
    const id = btn.dataset.exercise;
    const [level, note] = btn.querySelectorAll(".sub");

    // Exercises that aren't built yet say Coming soon
    if (!EXERCISES[id].built) {
      level.textContent = copy.COMING_SOON;
      note.textContent = "";
      continue;
    }

    const state = getTrainingState(id);
    level.textContent = copy.levelShort((state?.level ?? 0) + 1);

    // Say Not started, or the last level change, or the hits so far
    if (!state) {
      note.textContent = copy.NOT_STARTED;
    } else {
      note.textContent = copy.LAST_CHANGE[state.last] ?? copy.hitsSoFar(state.hits, HITS_TO_LEVEL_UP);
    }
  }
};


// Open an exercise when its card is tapped, or say it's not built yet
for (const btn of document.querySelectorAll("#screen-training [data-exercise]")) {
  btn.addEventListener("click", () => {
    const id = btn.dataset.exercise;
    if (EXERCISES[id].built) {
      location.hash = `#exercise/${id}`;
    } else {
      toast(copy.NOT_BUILT);
    }
  });
}


// THE EXERCISE SCREEN

const exSheet = $("ex-pad").parentElement;
const tapCanvas = $("ex-tap");
const tapSheet = tapCanvas.parentElement;

// The open exercise, with its id, level state, levels and the try in progress
let ex = null;


// The target for the current level
function exTarget() {
  return ex.levels[ex.state.level];
}


// The drawing, scoring and result setup for the open exercise
function exUI() {
  return EX_UI[ex.id];
}


// Every timer, animation frame and metronome click in use
let exTimers = [];
let exFrame = 0;
let exClicks = [];


// Stop every timer, animation and metronome click
function exStop() {
  for (const timer of exTimers) {
    clearTimeout(timer);
  }
  exTimers = [];

  cancelAnimationFrame(exFrame);

  for (const o of exClicks) {
    try {
      o.stop();
    } catch {}
  }
  exClicks = [];
}


// Run a step after a delay, and save the timer
function exAfter(ms, fn) {
  exTimers.push(setTimeout(fn, ms));
}


// Stop everything when the person leaves the exercise screen
addEventListener("hashchange", () => {
  if (!location.hash.startsWith("#exercise")) {
    exStop();
  }
});


// Show a short line above the pad, like Watch or Get ready
function exPhase(text) {
  $("ex-phase").textContent = text ?? "";
}


// Show one row of buttons, draw, start or next, and hide all three for anything else
function exActions(which) {
  $("ex-draw-actions").hidden = which !== "draw";
  $("ex-start-actions").hidden = which !== "start";
  $("ex-next-actions").hidden = which !== "next";
}


// Draw a line through the first upTo points of a path
function strokePath(ctx, path, upTo = path.x.length) {
  ctx.beginPath();
  for (let i = 0; i < upTo; i++) {
    if (i === 0) {
      ctx.moveTo(path.x[i], path.y[i]);
    } else {
      ctx.lineTo(path.x[i], path.y[i]);
    }
  }
  ctx.stroke();
}


// Draw a filled dot in the accent color
function dot(ctx, x, y, r) {
  ctx.fillStyle = cssVar("--accent");
  ctx.beginPath();
  ctx.arc(x, y, r, 0, 2 * Math.PI);
  ctx.fill();
}


// BIG WRITING

// The baseline sits at 80% of the pad's height, and the target line sits share of the height above it
function writingGeometry(w, h, share) {
  const baselineY = h * 0.8;
  return {
    baselineY,
    targetPx: h * share,
    targetY: baselineY - h * share,
    left: w * 0.06,
    right: w * 0.94,
  };
}


// Draw the baseline, the dashed target line and its label
function bigWritingGuide(ctx, w, h) {
  const g = writingGeometry(w, h, exTarget());
  ctx.save();

  // The solid baseline
  ctx.lineWidth = 2;
  ctx.strokeStyle = cssVar("--guide");
  ctx.beginPath();
  ctx.moveTo(g.left, g.baselineY);
  ctx.lineTo(g.right, g.baselineY);
  ctx.stroke();

  // The dashed target line
  ctx.setLineDash([10, 8]);
  ctx.strokeStyle = cssVar("--accent");
  ctx.beginPath();
  ctx.moveTo(g.left, g.targetY);
  ctx.lineTo(g.right, g.targetY);
  ctx.stroke();

  // The label at the right end of the target line
  ctx.fillStyle = cssVar("--ink2");
  ctx.font = `600 15px ${cssVar("--font-body")}`;
  ctx.textAlign = "right";
  ctx.fillText(copy.TARGET_LABEL, g.right, g.targetY - 10);
  ctx.restore();
}


// Draw a filled dot over each loop that reached the line, and a hollow dot over each that didn't
function loopMarks(ctx) {
  if (!ex.marks || !exPad.hasInk()) {
    return;
  }

  ctx.save();
  ctx.lineWidth = 2.5;
  for (const { x, y, reached } of ex.marks) {
    ctx.beginPath();
    ctx.arc(x, y - 14, 6, 0, 2 * Math.PI);
    if (reached) {
      ctx.fillStyle = cssVar("--accent");
    } else {
      ctx.fillStyle = cssVar("--surface");
    }
    ctx.strokeStyle = cssVar("--accent");
    ctx.fill();
    ctx.stroke();
  }
  ctx.restore();
}


// Unlock the pad and show the drawing buttons
function beginDrawing() {
  exSheet.inert = false;
  exActions("draw");
  exPhase(null);
}


// Score a big writing try, and save the pad size and target
function scoreBigWritingTry(samples, starts, w, h, recent) {
  const geo = writingGeometry(w, h, exTarget());
  return {
    out: scoreBigWriting(samples, starts, geo, recent),
    geometry: { width: w, height: h, baselineY: geo.baselineY, targetPx: geo.targetPx },
  };
}


// STEADY TRACING

// Seconds of watching the demo, then of picturing it
const DEMO_SECS = 4;
const IMAGINE_SECS = 4;
let spiralCache = null;


// The spiral for this pad size, made again only when the size changes
function spiralFor(w, h) {
  if (spiralCache?.w !== w || spiralCache?.h !== h) {
    spiralCache = { ...tracingPath(w, h), w, h };
  }
  return spiralCache;
}


// Draw the guide spiral and its start dot
function tracingGuide(ctx, w, h) {
  const path = spiralFor(w, h);

  // Show the spiral at full strength while watching and picturing, and at the level's strength while tracing
  let visibility = 1;
  if (ex.phase === "trace") {
    visibility = exTarget();
  }

  if (visibility > 0) {
    ctx.save();
    ctx.globalAlpha = visibility;
    ctx.strokeStyle = cssVar("--guide");
    ctx.lineWidth = Math.max(2, w / 180);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    strokePath(ctx, path);
    ctx.restore();
  }

  dot(ctx, path.x[0], path.y[0], 7.5);
}


// Draw the demo dot and the part of the spiral it has covered
function tracingOverlay(ctx, w, h) {
  if (ex.phase !== "watch" || ex.demoAt == null) {
    return;
  }

  const path = spiralFor(w, h);
  const along = ex.demoAt * path.length;
  ctx.save();
  ctx.strokeStyle = cssVar("--accent");
  ctx.lineWidth = Math.max(3, w / 110);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  // Find the first point past the demo dot, and draw the spiral up to it
  const upTo = path.s.findIndex((s) => s > along);
  if (upTo < 0) {
    strokePath(ctx, path, path.x.length);
  } else {
    strokePath(ctx, path, upTo);
  }
  ctx.restore();

  const [x, y] = pointAlong(path, along);
  dot(ctx, x, y, 9);
}


// Watch the demo, picture it during a countdown, then trace, with the pad locked until tracing starts
function beginTracing() {
  ex.phase = "watch";
  exSheet.inert = true;
  exActions("draw");
  $("ex-done").disabled = true;

  // The countdown for picturing the spiral, then unlock the pad for tracing
  const imagine = () => {
    ex.phase = "imagine";
    ex.demoAt = null;
    exPad.redraw();
    let left = IMAGINE_SECS;

    const tick = () => {
      if (left === 0) {
        ex.phase = "trace";
        exPad.redraw();
        exSheet.inert = false;
        exPhase(copy.TRACE_NOW);
        return;
      }
      exPhase(copy.imagine(left));
      left--;
      exAfter(1000, tick);
    };

    tick();
  };

  // With Reduced Motion on, show the spiral for a moment instead of the moving dot
  if (reduced()) {
    exPhase(copy.LOOK);
    exPad.redraw();
    exAfter(2500, imagine);
    return;
  }

  // Move the demo dot along the spiral over 4 seconds
  exPhase(copy.WATCH);
  const t0 = performance.now();
  const step = (now) => {
    ex.demoAt = Math.min(1, (now - t0) / 1000 / DEMO_SECS);
    exPad.redraw();
    if (ex.demoAt < 1) {
      exFrame = requestAnimationFrame(step);
    } else {
      exAfter(600, imagine);
    }
  };
  exFrame = requestAnimationFrame(step);
}


// Clear the drawing during tracing without playing the demo again
function clearTracing() {
  if (ex.phase !== "trace") {
    exNewTry();
    return;
  }

  exPad.reset();
  exSheet.inert = false;
  $("ex-done").disabled = true;
  showStatus($("ex-status"), null);
}


// Score a tracing try, and save the pad size, spiral size and visibility
function scoreTracingTry(samples, starts, w, h, recent) {
  const path = spiralFor(w, h);
  return {
    out: scoreTracing(samples, starts, path, recent),
    geometry: { width: w, height: h, radius: path.radius, visibility: exTarget() },
  };
}


// RHYTHM

let waveCache = null;


// The wave for this pad size, made again only when the size changes
function waveFor(w, h) {
  if (waveCache?.w !== w || waveCache?.h !== h) {
    waveCache = { ...rhythmPath(w, h), w, h };
  }
  return waveCache;
}


// Draw the guide wave
function rhythmGuide(ctx, w, h) {
  ctx.save();
  ctx.strokeStyle = cssVar("--guide");
  ctx.lineWidth = Math.max(2, w / 180);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  strokePath(ctx, waveFor(w, h));
  ctx.restore();
}


// Draw the dot on the wave, with a ring around it
function rhythmOverlay(ctx) {
  if (ex.phase === "done" || !waveCache) {
    return;
  }

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


// Show the wave with the dot at the start, and wait for the Start button
function beginRhythm() {
  ex.phase = "ready";
  ex.dotBeat = 0;
  exSheet.inert = true;
  exActions("start");
  exPhase(copy.RHYTHM_READY);
  exPad.redraw();
}

let audio = null;


// Play one metronome click at a set time on the audio clock, higher for the accented click
function click(at, accent) {
  const o = audio.createOscillator();
  const g = audio.createGain();

  if (accent) {
    o.frequency.value = 1320;
  } else {
    o.frequency.value = 880;
  }

  // A short click that rises fast and fades out
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(0.5, at + 0.004);
  g.gain.exponentialRampToValueAtTime(0.0001, at + 0.07);
  o.connect(g).connect(audio.destination);
  o.start(at);
  o.stop(at + 0.08);
  exClicks.push(o);
}


// Schedule the lead in clicks and the beats on the audio clock, and start the dot at the same time
function startRhythm() {
  const beatSec = 60 / exTarget();

  // The first click plays 0.15 seconds after the tap
  const lead = 0.15;

  // Schedule every click, and keep going without sound if audio doesn't work
  try {
    audio ??= new (window.AudioContext || window.webkitAudioContext)();

    // Turn the sound on
    audio.resume();

    const t0 = audio.currentTime + lead;
    for (let k = 0; k <= COUNT_IN + RHYTHM_BEATS; k++) {
      click(t0 + k * beatSec, k === COUNT_IN);
    }
  } catch (err) {
    console.warn("NeuroTrace: no metronome sound", err);
  }

  // The dot starts after the lead in clicks
  ex.dotStart = performance.now() + (lead + COUNT_IN * beatSec) * 1000;
  ex.phase = "count";

  // Unlock the pad during the lead in
  exSheet.inert = false;
  exActions("draw");
  $("ex-done").disabled = !exPad.hasInk();

  // Each frame, count down the lead in, then move the dot along the wave
  const step = (now) => {
    const t = (now - ex.dotStart) / 1000;

    if (t < 0) {
      const beatsLeft = Math.min(COUNT_IN, Math.ceil(-t / beatSec));
      exPhase(copy.getReady(beatsLeft));
    } else if (ex.phase === "count") {
      ex.phase = "run";
      exPhase(copy.FOLLOW);
    }

    ex.dotBeat = Math.min(RHYTHM_BEATS, Math.max(0, t / beatSec));
    exPad.redraw();

    if (t < RHYTHM_BEATS * beatSec) {
      exFrame = requestAnimationFrame(step);
    } else {
      ex.phase = "end";
      exPhase(copy.RHYTHM_END);
    }
  };
  exFrame = requestAnimationFrame(step);
}


// Score a rhythm try, and save the pad size, the beat speed and when the pen started
function scoreRhythmTry(samples, starts, w, h, recent) {
  const beatSec = 60 / exTarget();
  const first = exPad.startedAt();

  // Seconds from the dot starting to the pen's first touch, negative when the pen was down first
  let penOffset = 0;
  if (ex.dotStart != null && first != null) {
    penOffset = (first - ex.dotStart) / 1000;
  }

  return {
    out: scoreRhythm(samples, starts, waveFor(w, h), { beatSec, penOffset }, recent),
    geometry: { width: w, height: h, bpm: exTarget(), penOffset },
  };
}


// HAND SKILLS, TAPPING SHRINKING CIRCLES

// The pause between circles, and how far outside a circle a tap can land and still catch it
const GAP_MS = 400;
const TAP_SLACK = 6;

// The round in progress, with its results, stray taps, the current circle, whether a pen was seen and the input
let round = null;
let tapCtx = null;
let tapW = 0;
let tapH = 0;


// Size the tapping canvas to its space on the screen
function sizeTapCanvas() {
  const fit = fitCanvas(tapCanvas);
  tapCtx = fit.ctx;
  tapW = fit.w;
  tapH = fit.h;
}


// Size the canvas again and draw the circle when the screen changes size
new ResizeObserver(() => {
  if (tapSheet.hidden) {
    return;
  }
  sizeTapCanvas();
  paintTarget();
}).observe(tapCanvas);


// Draw the current circle at its size right now
function paintTarget(now = performance.now()) {
  if (!tapCtx) {
    return;
  }

  tapCtx.clearRect(0, 0, tapW, tapH);

  const t = round?.target;
  let r = 0;
  if (t) {
    r = targetRadius(t.size, (now - t.at) / 1000);
  }

  if (r > 0) {
    dot(tapCtx, t.x, t.y, r);
  }
}


// Show the empty canvas and wait for the Start button
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


// Start a new round, with the first circle after a short pause
function startTargets() {
  ex.phase = "run";
  exActions(null);
  round = { results: [], extra: 0, target: null, penSeen: false, inputType: null };
  sizeTapCanvas();
  exAfter(600, nextTarget);
}


// Show the next circle until it's caught or shrinks away, or end the round after the last circle
function nextTarget() {
  if (round.results.length >= TARGETS) {
    endRound();
    return;
  }

  // Put the circle at a random spot, with the whole circle at least 8 points inside the canvas
  const size = exTarget();
  const m = size / 2 + 8;
  round.target = {
    x: m + Math.random() * (tapW - 2 * m),
    y: m + Math.random() * (tapH - 2 * m),
    size,
    at: performance.now(),
  };
  exPhase(copy.circleOf(round.results.length + 1, TARGETS));

  // Each frame, shrink the circle, and count it as missed once it's gone
  const step = (now) => {
    const t = round?.target;
    if (!t) {
      return;
    }

    if (targetRadius(t.size, (now - t.at) / 1000) <= 0) {
      round.results.push({ caught: false, ms: null });
      round.target = null;
      paintTarget(now);
      exAfter(GAP_MS, nextTarget);
      return;
    }

    paintTarget(now);
    exFrame = requestAnimationFrame(step);
  };
  exFrame = requestAnimationFrame(step);
}


// Check each tap, counting a catch when it lands on the circle and a stray tap when it doesn't
tapCanvas.addEventListener("pointerdown", (e) => {
  if (ex?.phase !== "run" || !round) {
    return;
  }

  // Once a pen is seen, ignore touches from a resting palm
  if (e.pointerType === "pen") {
    round.penSeen = true;
  }
  if (e.pointerType === "touch" && round.penSeen) {
    return;
  }

  // Save the input from the first tap
  if (round.inputType == null) {
    if (e.pointerType === "pen") {
      round.inputType = "pencil";
    } else {
      round.inputType = e.pointerType;
    }
  }

  // Find where the tap landed and how big the circle is right now
  const t = round.target;
  const rect = tapCanvas.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const y = e.clientY - rect.top;
  let r = 0;
  if (t) {
    r = targetRadius(t.size, (e.timeStamp - t.at) / 1000);
  }

  // A tap on the circle catches it, and any other tap counts as stray, including taps between circles
  if (t && r > 0 && Math.hypot(x - t.x, y - t.y) <= r + TAP_SLACK) {
    round.results.push({ caught: true, ms: Math.round(e.timeStamp - t.at) });
    round.target = null;
    cancelAnimationFrame(exFrame);
    paintTarget();
    navigator.vibrate?.(10);
    exAfter(GAP_MS, nextTarget);
  } else {
    round.extra++;
  }
});


// Score the round once every circle is done
function endRound() {
  ex.phase = "done";
  exPhase(null);
  finishTry(scoreTargets(round.results, round.extra), {
    inputType: round.inputType,
    results: round.results,
    geometry: { width: tapW, height: tapH },
  });
}


// Each exercise's pad shape, drawing steps, start, scoring and result rows
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
    rows: ({ measures: m }) => {
      const needed = Math.ceil(CATCH_SHARE * m.targets);

      // The most stray taps allowed for this many catches, plus 1e-9 for rounding
      const maxExtra = Math.floor(m.caught / TAP_PRECISION - m.caught + 1e-9);

      return [
        ["caught", copy.caughtSentence(m.caught, m.targets, needed)],
        ["reaction", copy.reactionSentence(m.reactionMs)],
        ["extra", copy.extraTapsSentence(m.extraTaps, maxExtra)],
      ];
    },
  },
};


// The exercise drawing pad, which draws each exercise's guide and marks
const exPad = createPad($("ex-pad"), {
  onInk({ cleared }) {
    $("ex-done").disabled = exSheet.inert || !exPad.hasInk();
    if (cleared) {
      showStatus($("ex-status"), copy.RESIZE_CLEARED);
    } else {
      showStatus($("ex-status"), null);
    }
  },
  guide: (ctx, w, h) => {
    if (ex) {
      EX_UI[ex.id].guide?.(ctx, w, h);
    }
  },
  overlay: (ctx, w, h) => {
    if (ex) {
      EX_UI[ex.id].overlay?.(ctx, w, h);
    }
  },
});


// Show the level, the hits so far as dots, and the misses in a row
function renderExProgress() {
  const { state, levels } = ex;
  $("ex-level").textContent = copy.levelOf(state.level + 1, levels.length);
  const parts = [];

  // At the top level say so, otherwise show one dot per hit needed
  if (state.level === levels.length - 1) {
    parts.push(el("span", "sub", copy.TOP_LEVEL));
  } else {

    // Hide the dots from screen readers
    const dots = el("span", "hit-dots");
    dots.setAttribute("aria-hidden", "true");
    for (let i = 0; i < HITS_TO_LEVEL_UP; i++) {
      if (i < state.hits) {
        dots.append(el("span", "on"));
      } else {
        dots.append(el("span", null));
      }
    }
    parts.push(dots, el("span", "sub", copy.hitsSoFar(state.hits, HITS_TO_LEVEL_UP)));
  }

  if (state.misses) {
    parts.push(el("span", "sub", copy.missesInARow(state.misses, MISSES_TO_LEVEL_DOWN)));
  }

  $("ex-progress").replaceChildren(...parts);
  $("ex-too-hard").disabled = state.level === 0;
}


// Clear everything and start a new try
function exNewTry() {
  exStop();
  Object.assign(ex, { phase: null, marks: null, demoAt: null, dotBeat: null, dotStart: null });
  round = null;

  // Show the drawing pad or the tapping canvas, wide or square
  const ui = exUI();
  exSheet.hidden = ui.pad === "tap";
  tapSheet.hidden = ui.pad !== "tap";
  exSheet.classList.toggle("pad-wide", ui.pad === "wide");

  exPad.reset();
  showStatus($("ex-status"), null);
  $("ex-result").replaceChildren();
  ui.begin();
}


// Show the verdict, a note when the target was reached but slower or shakier, a row per measurement, and any level change
function renderExResult(out, change) {
  const id = ex.id;

  // Pick the verdict
  let verdict = copy.VERDICT_MISS;
  if (out.hit) {
    verdict = copy.VERDICT_HIT;
  } else if (out.reachedTarget) {
    verdict = copy.VERDICT_NOT_COUNTED[id];
  }

  // Add a note when the target was reached but the try was slower or shakier
  const notes = [];
  if (out.reachedTarget && !out.hit) {
    if (out.slower) {
      notes.push(copy.SLOWER_NOTES[id]);
    }
    if (out.shakier) {
      notes.push(copy.SHAKIER_NOTES[id]);
    }
  }

  // One row per measurement
  const rows = [];
  for (const [key, text] of exUI().rows(out)) {
    const row = el("div", "ex-row");
    row.append(el("span", "ex-row-name", copy.MEASURE_NAMES[key]), el("span", "sub", text));
    rows.push(row);
  }

  const noteParagraphs = [];
  for (const t of notes) {
    noteParagraphs.push(el("p", null, t));
  }

  const box = card(verdict, ...noteParagraphs, ...rows);

  // Say when the level went up or down
  if (change) {
    let levelCopy = copy.LEVEL_DOWN;
    if (change === "up") {
      levelCopy = copy.LEVEL_UP;
    }
    const message = levelCopy[id](ex.state.level + 1);
    box.append(el("p", "ex-level-note", message));
  }

  $("ex-result").replaceChildren(box);
}


// Update the level, save the try, and show the result
function finishTry(out, extra) {
  const before = ex.state;
  const { state, change } = applyTry(before, out, ex.levels.length);
  ex.state = state;
  setTrainingState(ex.id, state);

  // Save the try with its level, target, result and measurements
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

  // Scroll the result into view, with no smooth scroll when Reduced Motion is on
  let behavior = "smooth";
  if (reduced()) {
    behavior = "auto";
  }
  $("ex-result").scrollIntoView({ behavior, block: "nearest" });
}


// Open an exercise with its saved level
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


// The Clear button uses the exercise's own clear step, or starts a new try
$("ex-clear").addEventListener("click", () => {
  const clear = exUI().clear ?? exNewTry;
  clear();
});
$("ex-next").addEventListener("click", exNewTry);
$("ex-start").addEventListener("click", () => {
  exUI().start();
});


// Go down one level when the person says it's too hard
$("ex-too-hard").addEventListener("click", () => {
  const state = tooHard(ex.state);

  // Stop if already at Level 1
  if (state === ex.state) {
    return;
  }

  ex.state = state;
  setTrainingState(ex.id, state);
  renderExProgress();
  exNewTry();
  toast(copy.tooHardToast(state.level + 1));
});


// Score a drawing try when the Done button is tapped
$("ex-done").addEventListener("click", async () => {

  // Lock the pad and the button
  $("ex-done").disabled = true;
  exSheet.inert = true;

  const trace = exPad.trace();
  const starts = exPad.strokeStarts();
  const { width, height } = $("ex-pad").getBoundingClientRect();

  // Find the recent counted tries with the same input
  const tries = await listTrainingTries(ex.id).catch(() => []);
  const recent = [];
  for (const t of tries) {
    if (t.counted && t.inputType === trace.inputType) {
      recent.push(t.measures);
    }
  }

  const { out, geometry } = exUI().score(trace.samples, starts, width, height, recent);

  // If it's too short to judge, keep the drawing and unlock the pad
  if (!out.counted) {
    exSheet.inert = false;
    $("ex-done").disabled = !exPad.hasInk();
    showStatus($("ex-status"), exUI().tooShort);
    return;
  }

  // Stop the exercise, draw the marks and finish the try
  exStop();
  ex.phase = "done";
  ex.marks = out.marks ?? null;
  exPad.redraw();
  exPhase(null);
  finishTry(out, { inputType: trace.inputType, path: replayPath(trace.samples, starts), geometry });
});


// Export every practice try as a JSON file
$("export-practice").addEventListener("click", async () => {
  const tries = await listTrainingTries().catch(() => []);

  if (!tries.length) {
    toast(copy.NO_PRACTICE);
    return;
  }

  // Turn number arrays into plain lists rounded to 2 decimals
  const body = { formatVersion: 1, exportedAt: new Date().toISOString(), tries };
  const json = JSON.stringify(body, (k, v) => {
    if (!ArrayBuffer.isView(v)) {
      return v;
    }

    const rounded = [];
    for (const n of v) {
      rounded.push(Math.round(n * 100) / 100);
    }
    return rounded;
  });

  // Name the file with today's date and share or download it
  const name = `neurotrace-practice-${body.exportedAt.slice(0, 10)}.json`;
  const file = new File([json], name, { type: "application/json" });
  if (await shareFile(file)) {
    toast(copy.EXPORTED);
  }
});


// Buttons marked data-soon say Not built yet
for (const btn of document.querySelectorAll("[data-soon]")) {
  btn.addEventListener("click", () => {
    toast(copy.NOT_BUILT);
  });
}


// DATA COLLECTION

// Each collection session has 3 spirals
const COLLECT_TRIALS = 3;
let pendingId = null;


// Start a collection session for a participant
function startSession(subjectId, session) {
  collecting = { subjectId, session, trials: [] };
  location.hash = "#collect-details";
}


// Show a new participant id, the returning participants, and how many sessions haven't been exported
onShow.collect = async () => {
  let subs = [];
  let sessions = [];
  try {
    [subs, sessions] = await Promise.all([subjects(), listCollected()]);
  } catch (err) {
    console.warn("NeuroTrace: couldn't read collected sessions", err);
  }
  collecting = null;

  // Make a new id that no participant has yet
  const taken = new Set();
  for (const s of subs) {
    taken.add(s.subjectId);
  }
  pendingId = newSubjectId(taken);
  $("collect-new-id").textContent = pendingId;

  // List the returning participants, or say there are none
  const list = $("collect-returning");
  if (!subs.length) {
    list.replaceChildren(el("p", "sub", copy.NO_PARTICIPANTS));
  } else {
    const dateFmt = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" });
    const rows = [];

    for (const { subjectId, sessions: n, lastAt } of subs) {
      const row = el("button", "history-row returning-row");
      row.type = "button";

      // Say 1 session or 2 sessions
      let plural = "s";
      if (n === 1) {
        plural = "";
      }

      const text = el("span", "history-text");
      text.append(el("span", "history-when mono", subjectId),
        el("span", "sub", `${n} session${plural}, last on ${dateFmt.format(new Date(lastAt))}`));
      row.append(text);
      row.insertAdjacentHTML("beforeend", CHEVRON);

      // Tapping the row starts their next session
      row.addEventListener("click", () => {
        startSession(subjectId, n + 1);
      });
      rows.push(row);
    }

    list.replaceChildren(...rows);
  }

  // Count the sessions not exported yet
  const waiting = [];
  for (const s of sessions) {
    if (!s.exported) {
      waiting.push(s);
    }
  }

  let plural = "s";
  if (waiting.length === 1) {
    plural = "";
  }

  $("collect-unexported").hidden = !waiting.length;
  $("unexported-title").textContent = `${waiting.length} session${plural} not exported yet`;
};

$("collect-start").addEventListener("click", () => {
  startSession(pendingId, 1);
});


// Export every session that hasn't been exported yet as one file
$("collect-export-all").addEventListener("click", async () => {
  const all = await listCollected();
  const waiting = [];
  for (const s of all) {
    if (!s.exported) {
      waiting.push(s);
    }
  }

  if (!waiting.length) {
    return;
  }

  const day = new Date().toISOString().slice(0, 10);
  if (await exportSessions(waiting, `neurotrace-export-${day}.json`)) {
    onShow.collect();
  }
});


// THE PARTICIPANT DETAILS FORM

const detailsHelp = $("details-help");
const detailsBegin = $("details-begin");


// Find which option is picked in a group of choices on the form
function radio(name) {
  return document.querySelector(`#details-form input[name="${name}"]:checked`)?.value;
}


// Read the form, leaving out an age outside 18 to 110 and a medication time that isn't a number of hours
function readDetails() {
  const age = Number($("c-age").value);
  const med = $("c-med").value;
  const dx = radio("c-dx");

  let goodAge = null;
  if (Number.isInteger(age) && age >= 18 && age <= 110) {
    goodAge = age;
  }

  // The medication time only counts for people with Parkinson's
  let medicationHoursAgo = null;
  if (dx === "parkinsons" && med !== "" && Number(med) >= 0) {
    medicationHoursAgo = Number(med);
  }

  return {
    consent: $("c-consent").checked,
    age: goodAge,
    hand: radio("c-hand"),
    diagnosis: dx,
    medicationHoursAgo,
  };
}


// Show the age group and the medication question, and list anything still missing
function syncDetails() {
  const d = readDetails();

  if (d.age) {
    $("c-bracket").textContent = copy.bracketNote(d.age);
  } else {
    $("c-bracket").textContent = "";
  }

  $("c-med-row").hidden = d.diagnosis !== "parkinsons";

  // List everything still missing
  const missing = [];
  if (!d.consent) {
    missing.push("consent");
  }
  if (!d.age) {
    missing.push("an age from 18 to 110");
  }
  if (!d.hand) {
    missing.push("the drawing hand");
  }
  if (!d.diagnosis) {
    missing.push("a diagnosis");
  }

  // Turn on the Begin button only when nothing is missing
  detailsBegin.disabled = missing.length > 0;
  detailsHelp.hidden = !missing.length;
  if (missing.length) {
    detailsHelp.textContent = `Still needed: ${missing.join(", ")}.`;
  } else {
    detailsHelp.textContent = "";
  }
}


// Show the participant and session, and clear the form unless it was already filled in
onShow["collect-details"] = () => {
  $("details-session").innerHTML = `<span class="mono">${collecting.subjectId}</span>, session ${collecting.session}`;

  if (collecting.details) {
    syncDetails();
    return;
  }

  $("c-consent").checked = false;
  $("c-age").value = "";
  $("c-med").value = "";
  for (const r of document.querySelectorAll("#details-form input[type=radio]")) {
    r.checked = false;
  }
  syncDetails();
};

$("details-form").addEventListener("input", syncDetails);
$("details-form").addEventListener("change", syncDetails);

// Save the details and go to the drawing screen
detailsBegin.addEventListener("click", () => {
  collecting.details = readDetails();
  collecting.trials = [];
  location.hash = "#collect-draw";
});


// THE COLLECTION DRAWING SCREEN

const collectNext = $("collect-next");
const collectStatus = $("collect-status");
const collectSheet = $("collect-pad").parentElement;


// The collection drawing pad, which turns on the Next button once there's ink
const collectPad = createPad($("collect-pad"), {
  onInk({ cleared }) {
    collectNext.disabled = collectSheet.inert || !collectPad.hasInk();

    // If the pad was cleared from the screen changing size, say so and show the start dot again
    if (cleared) {
      showStatus(collectStatus, copy.RESIZE_CLEARED);
      collectPad.showStartDot(true);
    } else {
      showStatus(collectStatus, null);
    }
  },
});


// Clear the pad for the next spiral
function newCollectTrial() {
  const done = collecting.trials.length;
  $("collect-count").textContent = `Spiral ${done + 1} of ${COLLECT_TRIALS}`;
  $("collect-session").innerHTML = `<span class="mono">${collecting.subjectId}</span>, session ${collecting.session}`;
  progressDots($("collect-progress"), done, COLLECT_TRIALS);

  // The button says Finish on the last spiral
  if (done + 1 === COLLECT_TRIALS) {
    collectNext.textContent = "Finish";
  } else {
    collectNext.textContent = "Next spiral";
  }

  collectPad.reset();
  collectPad.showStartDot(true);
  collectSheet.inert = false;
  collectNext.disabled = true;
  showStatus(collectStatus, null);
}


// Start the spirals, or go back to the form if the details aren't filled in
onShow["collect-draw"] = () => {
  if (!collecting.details) {
    location.replace("#collect-details");
    return;
  }

  collecting.trials = [];
  newCollectTrial();
};

$("collect-redo").addEventListener("click", newCollectTrial);


// Ask before leaving a session that has a drawing in it
$("collect-back").addEventListener("click", (e) => {
  const drawnSome = collecting?.trials.length || collectPad.hasInk();
  if (drawnSome && !confirm(copy.LEAVE_SESSION)) {
    e.preventDefault();
  }
});


// Save each spiral, and after the last one save the session
collectNext.addEventListener("click", async () => {
  const trace = collectPad.trace(collecting.details.hand);

  // Check the spiral is long enough to measure
  try {
    featuresFromTrace(trace);
  } catch {
    showStatus(collectStatus, copy.TOO_SHORT);
    return;
  }

  collecting.trials.push(trace);
  navigator.vibrate?.(12);

  // Before the last spiral, show a saved message and clear the pad for the next one
  if (collecting.trials.length < COLLECT_TRIALS) {
    toast(copy.SPIRAL_SAVED(collecting.trials.length));
    newCollectTrial();
    return;
  }

  // Lock the pad
  collectNext.disabled = true;
  collectSheet.inert = true;
  const { subjectId, session, details, trials: traces } = collecting;

  // Keep only the time, position and pressure of each point
  const savedTrials = [];
  for (let i = 0; i < traces.length; i++) {
    const samples = [];
    for (const { t, x, y, pressure } of traces[i].samples) {
      samples.push({ t, x, y, pressure });
    }
    savedTrials.push({ trial: i + 1, task: "spiral", samples });
  }

  // Build the session record
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
    trials: savedTrials,
    exported: false,
  };

  // Save it on this iPad
  try {
    record.id = await saveCollected(record);
  } catch (err) {
    console.error("NeuroTrace: couldn't save the session on this iPad", err);
  }

  collecting.saved = record;
  location.hash = "#collect-done";
});


// Show a summary of the saved session
onShow["collect-done"] = () => {
  const s = collecting.saved;
  if (!s) {
    location.replace("#collect");
    return;
  }

  // Name the drawing hand and the input
  let hand = "Right";
  if (s.hand === "left") {
    hand = "Left";
  }
  const inputs = { pencil: "Apple Pencil", touch: "Finger", mouse: "Mouse" };
  const input = inputs[s.inputType] ?? s.inputType;

  const facts = [
    ["Participant", s.subjectId],
    ["Session", String(s.session)],
    ["Age", String(s.age)],
    ["Drawing hand", hand],
    ["Diagnosis", copy.DIAGNOSES[s.diagnosis]],
    ["Input", input],
  ];

  // One cell per fact
  const grid = el("dl", "card facts");
  for (const [k, v] of facts) {
    const cell = el("div");
    cell.append(el("dt", "sub", k), el("dd", null, v));
    grid.append(cell);
  }

  $("done-summary").replaceChildren(grid);
};


// Export the session that was just saved
$("done-export").addEventListener("click", async () => {
  const s = collecting?.saved;
  if (s) {
    await exportSessions([s], `${s.subjectId}-s${s.session}.json`);
  }
});


// Export sessions as a JSON file, and mark them as exported
async function exportSessions(sessions, filename) {

  // Leave out the id and exported fields
  const clean = [];
  for (const { id, exported, ...s } of sessions) {
    clean.push(s);
  }

  // Save one session on its own, and more than one as a list
  let data = clean;
  if (clean.length === 1) {
    data = clean[0];
  }
  const file = new File([JSON.stringify(data, null, 2)], filename, { type: "application/json" });

  if (!(await shareFile(file))) {
    return false;
  }

  // Mark the saved sessions as exported
  const ids = [];
  for (const s of sessions) {
    if (s.id != null) {
      ids.push(s.id);
    }
  }
  if (ids.length) {
    await markExported(ids).catch((err) => console.warn("NeuroTrace: couldn't mark sessions exported", err));
  }

  toast(copy.EXPORTED);
  return true;
}


// Share a file with the share sheet, or download it if sharing isn't available
// Return false if the person closed the share sheet
async function shareFile(file) {
  try {
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ files: [file], title: file.name });
    } else {
      download(file);
    }
  } catch (err) {
    if (err.name === "AbortError") {
      return false;
    }
    download(file);
  }
  return true;
}


// Download a file with a hidden link
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


// THE SETTINGS SCREEN

// Use light or dark mode, or follow the device
function applyTheme(theme) {
  if (theme === "light" || theme === "dark") {
    document.documentElement.dataset.theme = theme;
  } else {
    delete document.documentElement.dataset.theme;
  }
}

$("settings-age").innerHTML = ageChips("s-age");


// Pick the option with this value in a group of settings
function check(name, value) {
  for (const r of document.querySelectorAll(`#screen-settings input[name="${name}"]`)) {
    r.checked = r.value === value;
  }
}


// Make one button per accent color
const ACCENT_IDS = ["blue", "indigo", "violet", "teal", "amber", "rose", "graphite"];
let accentHtml = "";
for (let i = 0; i < copy.ACCENTS.length; i++) {
  accentHtml += `<label class="accent-option" data-accent="${ACCENT_IDS[i]}"><input type="radio" name="accent" value="${ACCENT_IDS[i]}" aria-label="${copy.ACCENTS[i]}"><span class="accent-dot"></span></label>`;
}
$("accent-choices").innerHTML = accentHtml;


// The name of an accent color, or Blue when it's unknown
function accentName(id) {
  return copy.ACCENTS[Math.max(0, ACCENT_IDS.indexOf(id))];
}


// Use an accent color, with blue as the default
function applyAccent(accent) {
  if (accent && accent !== "blue") {
    document.documentElement.dataset.accent = accent;
  } else {
    delete document.documentElement.dataset.accent;
  }
}


// Pick the saved settings
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


// Save a setting as soon as it changes
$("screen-settings").addEventListener("change", ({ target }) => {
  const { value } = target;

  // The theme and accent changes spread out from the center of the option that was tapped
  const r = target.closest("label").getBoundingClientRect();
  const from = { kind: "theme", x: r.left + r.width / 2, y: r.top + r.height / 2 };

  if (target.name === "s-age") {
    setPrefs({ ageChoice: value });
  }

  if (target.name === "s-hand") {
    setPrefs({ hand: value });
  }

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


// Delete every check-in after asking first
$("delete-all").addEventListener("click", async () => {
  if (!confirm(copy.DELETE_CONFIRM)) {
    return;
  }

  try {
    await clearAssessments();
    current = null;
    $("delete-status").textContent = copy.DELETED;
  } catch (err) {
    console.warn("NeuroTrace: couldn't delete check-ins", err);
    $("delete-status").textContent = copy.DELETE_FAILED;
  }
});


// Log out and go to the welcome screen
$("logout").addEventListener("click", () => {
  setPrefs({ signedIn: false });
  current = null;
  location.hash = "#home";
});


// THE WELCOME SCREEN

// Fill in the How it works steps
const howSteps = [];
for (const step of copy.HOW_STEPS) {
  howSteps.push(el("li", null, step));
}
$("how-steps").replaceChildren(...howSteps);


// Log in, and send people who haven't agreed yet to the consent screen first
$("login").addEventListener("click", () => {
  if (!getPrefs().consented) {
    location.hash = "#consent";
    return;
  }
  setPrefs({ signedIn: true });
  location.hash = "#dashboard";
});


// Show who you are compared with, or hide it if the scoring files didn't load
onShow.home = async () => {
  try {
    const { reference } = await scoring;
    const all = reference.brackets.all;
    $("about-reference").textContent = copy.referenceSentence({
      referenceN: all.n, bracketKey: "all", deviceMatched: reference.deviceMatched === true,
    });
    $("about-reference").hidden = false;
  } catch {
    $("about-reference").hidden = true;
  }
};


// STARTING THE APP

// Use the saved theme, accent and motion settings, and follow the device's Reduced Motion setting
applyTheme(getPrefs().theme);
applyAccent(getPrefs().accent);
applyMotion(getPrefs().motion);
matchMedia("(prefers-reduced-motion: reduce)").addEventListener("change", () => {
  applyMotion(getPrefs().motion);
});

// Move the tab highlight when the screen changes size
const tabbarEl = $("tabbar");
addEventListener("resize", () => {
  moveLens(tabbarEl);
});

// Fill in the steps on the measuring screen
const measureSteps = [];
for (const step of copy.MEASURE_STEPS) {
  measureSteps.push(el("li", null, step));
}
$("measuring-steps").replaceChildren(...measureSteps);

mountMascots();

// With Reduced Motion on, stop the welcome screen animation
if (reduced()) {
  for (const svg of document.querySelectorAll(".hero svg")) {
    svg.pauseAnimations();
  }
}


// Show why the scoring files didn't load
onShow.error = () => {
  $("error-message").textContent = loadError.message;
};


// Fill in every element marked data-copy with its text from copy.js
for (const node of document.querySelectorAll("[data-copy]")) {
  const words = [];
  for (const key of node.dataset.copy.split(" ")) {
    words.push(copy[key]);
  }
  node.textContent = words.join(" ");
}

drawArt();

// Show the right screen now and whenever the address changes
addEventListener("hashchange", route);
route();