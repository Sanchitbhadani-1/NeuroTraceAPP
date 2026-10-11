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

function scoreArray(below) {
  return Array(below).fill(0).concat(Array(1000 - below).fill(1));
}

function block({ n = 40, mean = [0, 0], sd = [1, 1], score = scoreArray(500) } = {}) {
  return { n, mean, sd, features: { f0: [0, 1, 2], f1: [0, 1, 2] }, score };
}

const flatModel = { version: 2, featureOrder: ORDER, weights: [0, 0], bias: 0 };
const perTrial = [{ f0: 5, f1: 5 }];

for (const [below, wantTier] of [[749, 0], [750, 1], [950, 2]]) {
  const reference = { minBracketN: 1, deviceMatched: true, trialsPerSession: 1,
    brackets: { all: block({ score: scoreArray(below) }) } };
  const r = scoreSession(perTrial, flatModel, reference, null);
  assert.equal(r.scorePct, below / 1000);
  assert.equal(r.tier, wantTier, `scorePct ${r.scorePct} should give tier ${wantTier}`);
}

const refBrackets = {
  minBracketN: 12,
  brackets: {
    all: block({ n: 40 }),
    "60s": block({ n: 5 }),
    "70s": block({ n: 20 }),
  },
};
assert.equal(bracketFor(refBrackets, "80+").key, "all");
assert.equal(bracketFor(refBrackets, "60s").key, "all");
assert.equal(bracketFor(refBrackets, null).key, "all");
assert.equal(bracketFor(refBrackets, undefined).key, "all");
assert.equal(bracketFor(refBrackets, "70s").key, "70s");
assert.equal(bracketFor(refBrackets, "70s").block, refBrackets.brackets["70s"]);

{
  const model = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const reference = { minBracketN: 1, deviceMatched: false, trialsPerSession: 1,
    brackets: { all: block() } };
  const r = scoreSession([{ f0: 5, f1: NaN }], model, reference, null);
  assert.equal(r.features.f0, 5);
  assert.ok(Number.isNaN(r.features.f1));
  assert.ok("f0" in r.measurePct);
  assert.ok(!("f1" in r.measurePct));
  assert.deepEqual(r.topSignals, ["f0"]);
}

{
  const model = { version: 2, featureOrder: ORDER, weights: [1, 1], bias: 0 };
  const reference = { minBracketN: 1, deviceMatched: false, trialsPerSession: 1,
    brackets: { all: block({ sd: [0, NaN] }) } };
  const r = scoreSession([{ f0: 5, f1: 5 }], model, reference, null);
  assert.equal(r.score, 0.5);
}

{
  const avg = averageFeatures([{ f0: 1 }, { f0: NaN }, { f0: 3 }], ["f0"]);
  assert.equal(avg.f0, 2);
  const allNaN = averageFeatures([{ f0: NaN }, { f0: NaN }], ["f0"]);
  assert.ok(Number.isNaN(allNaN.f0));
}

{
  const model = { version: 2, featureOrder: ["f0", "f1", "f2"], weights: [1, -1, 1], bias: 0 };
  const reference = { minBracketN: 1, deviceMatched: false, trialsPerSession: 1,
    brackets: { all: { n: 10, mean: [0, 0, 0], sd: [1, 1, 1],
      features: { f0: [0], f1: [0], f2: [0] }, score: scoreArray(500) } } };
  const r = scoreSession([{ f0: 2, f1: 2, f2: 1 }], model, reference, null);
  assert.deepEqual(r.topSignals, ["f0", "f2", "f1"]);
}

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

{
  const model = JSON.parse(fs.readFileSync(new URL("../model.json", import.meta.url)));
  const reference = JSON.parse(fs.readFileSync(new URL("../reference.json", import.meta.url)));
  assert.doesNotThrow(() => checkScoringFiles(model, reference, SPIRAL_FEATURE_ORDER));
}

assert.equal(fractionBelow(5, [1, 2, 3, 4, 5, 6]), 4 / 6);

{
  const validGroups = new Set(GROUPS.map((g) => g.id));
  for (const k of SPIRAL_FEATURE_ORDER) {
    assert.ok(MEASURES[k], `MEASURES is missing "${k}"`);
    assert.ok(validGroups.has(MEASURES[k].group), `MEASURES.${k}.group is not a real group`);
  }
}

{
  const { hi, lo } = MEASURES.spiral_duration;
  assert.equal(measureSentence("spiral_duration", 0.5), `${hi} 50% of the reference group`);
  assert.equal(measureSentence("spiral_duration", 0.86), `${hi} 86% of the reference group`);
  assert.equal(measureSentence("spiral_duration", 0.23), `${lo} 77% of the reference group`);
}

console.log("SCORE OK");
