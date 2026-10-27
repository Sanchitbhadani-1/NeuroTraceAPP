// SCORE-CHECK.MJS TESTS SCORE.JS ON A MADE UP MODEL AND REFERENCE GROUP
// IT CHECKS RESULT LEVELS, AGE GROUPS, MISSING VALUES, WHAT STOOD OUT, THE SCORING FILES AND THE SENTENCES
// RUN IT FROM THE REPO FOLDER WITH node app/tools/score-check.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import {
  checkScoringFiles,
  bracketFor,
  averageFeatures,
  scoreSession,
  fractionBelow,
} from "../core/score.js";
import { MEASURES, GROUPS, measureSentence } from "../old-website/copy.js";
import { SPIRAL_FEATURE_ORDER } from "../core/nt-features.js";

// The names of the two made up measurements
const ORDER = ["f0", "f1"];


// Make 1000 made up reference scores, with the first ones at 0 and the rest at 1
function scoreArray(below) {
  const scores = [];
  for (let i = 0; i < 1000; i++) {
    if (i < below) {
      scores.push(0);
    } else {
      scores.push(1);
    }
  }
  return scores;
}


// Make a made up reference group for the two measurements
function block({ n = 40, mean = [0, 0], sd = [1, 1], score = scoreArray(500) } = {}) {
  return {
    n,
    mean,
    sd,
    features: { f0: [0, 1, 2], f1: [0, 1, 2] },
    score,
  };
}


// A model that gives every check-in a score of 0.5
const flatModel = { version: 2, featureOrder: ORDER, weights: [0, 0], bias: 0 };

// One made up trial
const perTrial = [{ f0: 5, f1: 5 }];

// How many reference scores fall below 0.5, and the result level that should give
const tierCases = [
  [749, 0],
  [750, 1],
  [950, 2],
];

// Under 75% of the reference group below is level 0, under 95% is level 1, and 95% or more is level 2
for (const [below, wantTier] of tierCases) {
  const reference = {
    minBracketN: 1,
    deviceMatched: true,
    trialsPerSession: 1,
    brackets: { all: block({ score: scoreArray(below) }) },
  };
  const r = scoreSession(perTrial, flatModel, reference, null);
  assert.equal(r.scorePct, below / 1000);
  assert.equal(r.tier, wantTier, `scorePct ${r.scorePct} should give tier ${wantTier}`);
}

// A reference with an age group too small to use, and one big enough
const refBrackets = {
  minBracketN: 12,
  brackets: {
    all: block({ n: 40 }),
    "60s": block({ n: 5 }),
    "70s": block({ n: 20 }),
  },
};

// An age group that's missing, too small, or not given falls back to everyone
assert.equal(bracketFor(refBrackets, "80+").key, "all");
assert.equal(bracketFor(refBrackets, "60s").key, "all");
assert.equal(bracketFor(refBrackets, null).key, "all");
assert.equal(bracketFor(refBrackets, undefined).key, "all");

// An age group with at least 12 people is used
assert.equal(bracketFor(refBrackets, "70s").key, "70s");
assert.equal(bracketFor(refBrackets, "70s").block, refBrackets.brackets["70s"]);

// A measurement that came out NaN stays NaN, gets no place, and is left out of what stood out
{
  const model = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const reference = {
    minBracketN: 1,
    deviceMatched: false,
    trialsPerSession: 1,
    brackets: { all: block() },
  };
  const r = scoreSession([{ f0: 5, f1: NaN }], model, reference, null);
  assert.equal(r.features.f0, 5);
  assert.ok(Number.isNaN(r.features.f1));
  assert.ok("f0" in r.measurePct);
  assert.ok(!("f1" in r.measurePct));
  assert.deepEqual(r.topSignals, ["f0"]);
}

// A reference spread of 0 or NaN adds nothing to the score
{
  const model = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const reference = {
    minBracketN: 1,
    deviceMatched: false,
    trialsPerSession: 1,
    brackets: { all: block({ sd: [0, NaN] }) },
  };
  const r = scoreSession([{ f0: 5, f1: 5 }], model, reference, null);
  assert.equal(r.score, 0.5);
}

// The average skips NaN trials, and is NaN when every trial is NaN
{
  const avg = averageFeatures([{ f0: 1 }, { f0: NaN }, { f0: 3 }], ["f0"]);
  assert.equal(avg.f0, 2);
  const allNaN = averageFeatures([{ f0: NaN }, { f0: NaN }], ["f0"]);
  assert.ok(Number.isNaN(allNaN.f0));
}

// What stood out is sorted by how much each measurement pushed the score up
{
  const model = { version: 2, featureOrder: ["f0", "f1", "f2"], weights: [1, -1, 1], bias: 0 };
  const reference = {
    minBracketN: 1,
    deviceMatched: false,
    trialsPerSession: 1,
    brackets: {
      all: {
        n: 10,
        mean: [0, 0, 0],
        sd: [1, 1, 1],
        features: { f0: [0], f1: [0], f2: [0] },
        score: scoreArray(500),
      },
    },
  };
  const r = scoreSession([{ f0: 2, f1: 2, f2: 1 }], model, reference, null);
  assert.deepEqual(r.topSignals, ["f0", "f2", "f1"]);
}

// Matching scoring files pass, and a wrong order, wrong number of weights, old version or missing groups fail
{
  const goodModel = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const goodRef = {
    version: 2,
    featureOrder: ORDER,
    minBracketN: 1,
    brackets: { all: block() },
  };
  assert.doesNotThrow(() => checkScoringFiles(goodModel, goodRef, ORDER));
  assert.throws(() => checkScoringFiles({ ...goodModel, featureOrder: ["f1", "f0"] }, goodRef, ORDER));
  assert.throws(() => checkScoringFiles({ ...goodModel, weights: [1] }, goodRef, ORDER));
  assert.throws(() => checkScoringFiles({ ...goodModel, version: 1 }, goodRef, ORDER));
  assert.throws(() => checkScoringFiles(goodModel, { ...goodRef, brackets: {} }, ORDER));
}

// The real model.json and reference.json in the app pass the check
{
  const model = JSON.parse(fs.readFileSync(new URL("../old-website/model.json", import.meta.url)));
  const reference = JSON.parse(fs.readFileSync(new URL("../old-website/reference.json", import.meta.url)));
  assert.doesNotThrow(() => checkScoringFiles(model, reference, SPIRAL_FEATURE_ORDER));
}

// Only values strictly below count, not equal ones
assert.equal(fractionBelow(5, [1, 2, 3, 4, 5, 6]), 4 / 6);

// Every one of the 12 measurements has a name in copy.js and belongs to a real group
{
  const validGroups = new Set();
  for (const g of GROUPS) {
    validGroups.add(g.id);
  }
  for (const k of SPIRAL_FEATURE_ORDER) {
    assert.ok(MEASURES[k], `MEASURES is missing "${k}"`);
    assert.ok(validGroups.has(MEASURES[k].group), `MEASURES.${k}.group is not a real group`);
  }
}

// A place of 50% or more uses the hi wording, and below 50% uses the lo wording with 100 minus the place
{
  const { hi, lo } = MEASURES.spiral_duration;
  assert.equal(measureSentence("spiral_duration", 0.5), `${hi} 50% of the reference group`);
  assert.equal(measureSentence("spiral_duration", 0.86), `${hi} 86% of the reference group`);
  assert.equal(measureSentence("spiral_duration", 0.23), `${lo} 77% of the reference group`);
}

console.log("SCORE OK");