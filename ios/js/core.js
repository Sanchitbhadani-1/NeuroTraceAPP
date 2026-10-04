// The team's JavaScript, bundled into NeuroTrace/Resources/nt-core.js for the iPad app (see build.sh).
// The app runs it with JavaScriptCore and calls it through NT.call, with JSON going in and out

import * as features from "../../app/nt-features.js";
import * as score from "../../app/score.js";
import * as train from "../../app/train.js";
import * as tapping from "../../app/tapping.js";
import * as homescan from "../../app/homescan.js";
import * as meds from "../../app/meds.js";
import * as hands from "../../app/hands.js";

// BANNED is a regular expression, which JSON can't carry, so the app asks through this instead
const helpers = {
  isBanned: (text) => homescan.BANNED.test(text),
};

const modules = { features, score, train, tapping, homescan, meds, hands, helpers };

// JSON has no NaN or Infinity, so they travel as these words and turn back into numbers on arrival
const NAN = "__ntNaN";
const INF = "__ntInf";
const NEG_INF = "__ntNegInf";

// Objects kept here between calls, like a path the app reads every frame. The oldest go once there are too many
const kept = new Map();
let nextKept = 1;
const MAX_KEPT = 32;

function revive(key, value) {
  if (value === NAN) return NaN;
  if (value === INF) return Infinity;
  if (value === NEG_INF) return -Infinity;
  if (value !== null && typeof value === "object" && typeof value.__ntRef === "number") return kept.get(value.__ntRef);
  return value;
}

function replace(key, value) {
  if (typeof value === "number" && !Number.isFinite(value)) return Number.isNaN(value) ? NAN : value > 0 ? INF : NEG_INF;
  // Typed arrays would turn into objects with numbered keys, so they go as plain arrays
  if (ArrayBuffer.isView(value)) return Array.from(value);
  return value;
}

function find(path) {
  let value = modules;
  for (const part of path.split(".")) {
    if (value === undefined || value === null || !(part in Object(value))) throw new Error(`NT has no ${path}`);
    value = value[part];
  }
  return value;
}

function run(path, argsJSON) {
  const target = find(path);
  return typeof target === "function" ? target(...JSON.parse(argsJSON, revive)) : target;
}

// Calls a function (or reads a value) by its path, like "train.applyTry". The answer comes back as JSON, under v
export function call(path, argsJSON) {
  const value = run(path, argsJSON);
  return JSON.stringify({ v: value === undefined ? null : value }, replace);
}

// The same, but the answer also stays here. Its ref comes back too, so later calls can hand it back by ref
export function callKeep(path, argsJSON) {
  const value = run(path, argsJSON);
  const ref = nextKept++;
  kept.set(ref, value);
  if (kept.size > MAX_KEPT) kept.delete(kept.keys().next().value);
  return JSON.stringify({ v: value, ref }, replace);
}
