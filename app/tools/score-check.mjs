// Assert-based check for score.js and copy.js's measure metadata. Not a
// framework - just the smallest thing that fails when the scoring logic
// breaks. Run: node app/tools/score-check.mjs
//
// An uncaught AssertionError already exits non-zero with a stack pointing at
// the failing line, so no wrapping try/catch is needed here.

import assert from "node:assert/strict";
import fs from "node:fs";
import {
  checkScoringFiles,
  bracketFor,
  averageFeatures,
  scoreSession,
  fractionBelow,
} from "../score.js";
import { MEASURES, GROUPS, measureSentence } from "../copy.js";
import { SPIRAL_FEATURE_ORDER } from "../nt-features.js";

const ORDER = ["f0", "f1"];

// A "score" reference of 1000 values, `below` of which are less than 0.5 -
// gives fractionBelow(0.5, ...) an exact, easy-to-name fraction.
function scoreArray(below) {
  return Array(below).fill(0).concat(Array(1000 - below).fill(1));
}

function block({ n = 40, mean = [0, 0], sd = [1, 1], score = scoreArray(500) } = {}) {
  return { n, mean, sd, features: { f0: [0, 1, 2], f1: [0, 1, 2] }, score };
}

// --- tier cut points ---------------------------------------------------
// weights = 0 makes score depend only on bias (sigmoid(0) = 0.5), so the
// bracket's score array alone controls scorePct - and therefore the tier.
const flatModel = { version: 2, featureOrder: ORDER, weights: [0, 0], bias: 0 };
const perTrial = [{ f0: 5, f1: 5 }];

for (const [below, wantTier] of [[749, 0], [750, 1], [950, 2]]) {
  const reference = { minBracketN: 1, deviceMatched: true, trialsPerSession: 1,
    brackets: { all: block({ score: scoreArray(below) }) } };
  const r = scoreSession(perTrial, flatModel, reference, null);
  assert.equal(r.scorePct, below / 1000);
  assert.equal(r.tier, wantTier, `scorePct ${r.scorePct} should give tier ${wantTier}`);
}

// --- bracket fallback ----------------------------------------------------
const refBrackets = {
  minBracketN: 12,
  brackets: {
    all: block({ n: 40 }),
    "60s": block({ n: 5 }),  // thin - below minBracketN
    "70s": block({ n: 20 }), // healthy - should NOT fall back
  },
};
assert.equal(bracketFor(refBrackets, "80+").key, "all");   // missing bracket
assert.equal(bracketFor(refBrackets, "60s").key, "all");   // thin bracket
assert.equal(bracketFor(refBrackets, null).key, "all");    // null key
assert.equal(bracketFor(refBrackets, undefined).key, "all");
assert.equal(bracketFor(refBrackets, "70s").key, "70s");
assert.equal(bracketFor(refBrackets, "70s").block, refBrackets.brackets["70s"]);

// --- NaN feature contributes nothing and is omitted from measurePct ------
{
  const model = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const reference = { minBracketN: 1, deviceMatched: false, trialsPerSession: 1,
    brackets: { all: block() } };
  const r = scoreSession([{ f0: 5, f1: NaN }], model, reference, null);
  assert.equal(r.features.f0, 5);
  assert.ok(Number.isNaN(r.features.f1));
  assert.ok("f0" in r.measurePct);
  assert.ok(!("f1" in r.measurePct));
  // f1's z is 0 (no vote), so only f0's weight*z shows up as a signal.
  assert.deepEqual(r.topSignals, ["f0"]);
}

// --- zero/NaN sd guarded ---------------------------------------------------
{
  const model = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const reference = { minBracketN: 1, deviceMatched: false, trialsPerSession: 1,
    brackets: { all: block({ sd: [0, NaN] }) } };
  const r = scoreSession([{ f0: 5, f1: 5 }], model, reference, null);
  // Both z forced to 0 despite finite features -> zsum stays at bias -> score 0.5.
  assert.equal(r.score, 0.5);
}

// --- averaging ignores NaN trials ------------------------------------------
{
  const avg = averageFeatures([{ f0: 1 }, { f0: NaN }, { f0: 3 }], ["f0"]);
  assert.equal(avg.f0, 2);
  const allNaN = averageFeatures([{ f0: NaN }, { f0: NaN }], ["f0"]);
  assert.ok(Number.isNaN(allNaN.f0));
}

// --- topSignals is signed-descending ---------------------------------------
{
  const model = { version: 2, featureOrder: ["f0", "f1", "f2"], weights: [1, -1, 1], bias: 0 };
  // z: f0 -> +2, f1 -> +2 (weight -1 => signal -2), f2 -> +1 (signal +1)
  const reference = { minBracketN: 1, deviceMatched: false, trialsPerSession: 1,
    brackets: { all: { n: 10, mean: [0, 0, 0], sd: [1, 1, 1],
      features: { f0: [0], f1: [0], f2: [0] }, score: scoreArray(500) } } };
  const r = scoreSession([{ f0: 2, f1: 2, f2: 1 }], model, reference, null);
  assert.deepEqual(r.topSignals, ["f0", "f2", "f1"]); // signals +2, +1, -2
}

// --- checkScoringFiles: reordered featureOrder / wrong-length weights ------
{
  const goodModel = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const goodRef = { version: 2, featureOrder: ORDER, minBracketN: 1,
    brackets: { all: block() } };
  assert.doesNotThrow(() => checkScoringFiles(goodModel, goodRef, ORDER));
  assert.throws(() => checkScoringFiles({ ...goodModel, featureOrder: ["f1", "f0"] }, goodRef, ORDER));
  assert.throws(() => checkScoringFiles({ ...goodModel, weights: [1] }, goodRef, ORDER));
  assert.throws(() => checkScoringFiles({ ...goodModel, version: 1 }, goodRef, ORDER));
  assert.throws(() => checkScoringFiles(goodModel, { ...goodRef, brackets: {} }, ORDER));
}

// --- checkScoringFiles against the real files -------------------------------
{
  const model = JSON.parse(fs.readFileSync(new URL("../model.json", import.meta.url)));
  const reference = JSON.parse(fs.readFileSync(new URL("../reference.json", import.meta.url)));
  assert.doesNotThrow(() => checkScoringFiles(model, reference, SPIRAL_FEATURE_ORDER));
}

// --- fractionBelow itself ----------------------------------------------------
assert.equal(fractionBelow(5, [1, 2, 3, 4, 5, 6]), 4 / 6); // strict: 5 itself doesn't count

// --- every SPIRAL_FEATURE_ORDER key has a MEASURES entry with a valid group -
{
  const validGroups = new Set(GROUPS.map((g) => g.id));
  for (const k of SPIRAL_FEATURE_ORDER) {
    assert.ok(MEASURES[k], `MEASURES is missing "${k}"`);
    assert.ok(validGroups.has(MEASURES[k].group), `MEASURES.${k}.group is not a real group`);
  }
}

// --- measureSentence wording -------------------------------------------------
{
  const { hi, lo } = MEASURES.spiral_duration;
  assert.equal(measureSentence("spiral_duration", 0.5), `${hi} 50% of the reference group`);
  assert.equal(measureSentence("spiral_duration", 0.86), `${hi} 86% of the reference group`);
  assert.equal(measureSentence("spiral_duration", 0.23), `${lo} 77% of the reference group`);
}

console.log("SCORE OK");
