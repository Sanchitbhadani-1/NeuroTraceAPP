// CORE.JS GATHERS THE TEAM'S JAVASCRIPT INTO ONE BUNDLE FOR THE IOS APP
// BUILD.SH TURNS IT INTO NEUROTRACE/RESOURCES/NT-CORE.JS
// THE APP CALLS IT THROUGH NT.CALL, SENDING AND GETTING BACK JSON

// Bring in each part of the team's JavaScript
import * as features from "../../app/core/nt-features.js";
import * as score from "../../app/core/score.js";
import * as train from "../../app/core/train.js";
import * as tapping from "../../app/core/tapping.js";
import * as homescan from "../../app/core/homescan.js";
import * as meds from "../../app/core/meds.js";
import * as hands from "../../app/core/hands.js";

// Extra functions the app can call, isBanned checks text against homescan's BANNED words
const helpers = {
  isBanned: (text) => homescan.BANNED.test(text),
};

// Every part the app can reach, by name
const modules = { features, score, train, tapping, homescan, meds, hands, helpers };

// The words that stand in for NaN, Infinity and negative Infinity in JSON
const NAN = "__ntNaN";
const INF = "__ntInf";
const NEG_INF = "__ntNegInf";

// The answers kept between calls, the number for the next one, and the most that can be kept
const kept = new Map();
let nextKept = 1;
const MAX_KEPT = 32;

// Turn the stand in words back into numbers, and each { __ntRef } back into its kept answer
function revive(key, value) {
  if (value === NAN) return NaN;
  if (value === INF) return Infinity;
  if (value === NEG_INF) return -Infinity;
  if (value !== null && typeof value === "object" && typeof value.__ntRef === "number") return kept.get(value.__ntRef);
  return value;
}

// Turn NaN and the Infinities into their stand in words
function replace(key, value) {
  if (typeof value === "number" && !Number.isFinite(value)) return Number.isNaN(value) ? NAN : value > 0 ? INF : NEG_INF;

  // Turn typed arrays into plain arrays
  if (ArrayBuffer.isView(value)) return Array.from(value);
  return value;
}

// Find a function or value by its dotted path, like "train.applyTry"
// Throw an error if any part of the path is missing
function find(path) {
  let value = modules;
  for (const part of path.split(".")) {
    if (value === undefined || value === null || !(part in Object(value))) throw new Error(`NT has no ${path}`);
    value = value[part];
  }
  return value;
}

// Call the function at the path with the JSON arguments, or give back the value if it isn't a function
function run(path, argsJSON) {
  const target = find(path);
  return typeof target === "function" ? target(...JSON.parse(argsJSON, revive)) : target;
}

// Run the path and give back the answer as JSON under v, with null for undefined
export function call(path, argsJSON) {
  const value = run(path, argsJSON);
  return JSON.stringify({ v: value === undefined ? null : value }, replace);
}

// Run the path, keep the answer under a new ref number, and give back the answer and ref as JSON
export function callKeep(path, argsJSON) {
  const value = run(path, argsJSON);
  const ref = nextKept++;
  kept.set(ref, value);

  // Remove the oldest kept answer when there are more than MAX_KEPT
  if (kept.size > MAX_KEPT) kept.delete(kept.keys().next().value);
  return JSON.stringify({ v: value, ref }, replace);
}
