// HANDS-CHECK.MJS TESTS HANDS.JS ON MADE UP CHECK-INS
// IT CHECKS WHICH LEFT AND RIGHT HAND CHECK-INS GET PAIRED UP, AND HOW THE TWO HANDS ARE COMPARED
// RUN IT FROM THE REPO FOLDER WITH node app/tools/hands-check.mjs

import assert from "node:assert/strict";
import { latestPair, compareHands } from "../hands.js";

// One day in milliseconds
const DAY = 86400000;


// Make a made up check-in with a hand, a day, an input and its measurements
function rec(hand, day, inputType = "pencil", measurePct = {}) {
  return { ts: day * DAY, hand, inputType, measurePct };
}


// Get the measurement names from a list of rows, in order
function keysOf(rows) {
  const keys = [];
  for (const r of rows) {
    keys.push(r.key);
  }
  return keys;
}


// With no check-ins, or only left hand check-ins, there's no pair
assert.equal(latestPair({ records: [] }), null);
assert.equal(latestPair({ records: [rec("left", 10), rec("left", 9)] }), null);

// A left and a right check-in a day apart pair up
let pair = latestPair({ records: [rec("left", 10), rec("right", 9)] });
assert.equal(pair.left.ts, 10 * DAY);
assert.equal(pair.right.ts, 9 * DAY);

// Check-ins with different inputs don't pair
assert.equal(latestPair({ records: [rec("left", 10, "pencil"), rec("right", 9, "finger")] }), null);

// Check-ins more than 7 days apart don't pair, and exactly 7 days apart do
assert.equal(latestPair({ records: [rec("left", 20), rec("right", 12)] }), null);
assert.notEqual(latestPair({ records: [rec("left", 19), rec("right", 12)] }), null);

// With more than one possible pair, the newest left and right check-ins pair up
pair = latestPair({ records: [rec("left", 18), rec("left", 16), rec("right", 15), rec("right", 12)] });
assert.equal(pair.left.ts, 18 * DAY);
assert.equal(pair.right.ts, 15 * DAY);

// The pair whose older check-in is newest wins, then the pair whose newer check-in is newest
pair = latestPair({ records: [rec("left", 18), rec("left", 16), rec("right", 16), rec("right", 3), rec("left", 2)] });
assert.equal(pair.left.ts, 18 * DAY);
assert.equal(pair.right.ts, 16 * DAY);

// The order of the check-ins doesn't change the pair
pair = latestPair({ records: [rec("right", 1), rec("left", 2), rec("left", 3)] });
assert.equal(pair.left.ts, 3 * DAY);

// Pencil pairs and finger pairs are found separately, and the newest one wins
pair = latestPair({
  records: [rec("left", 10, "finger"), rec("right", 10, "finger"), rec("left", 8, "pencil"), rec("right", 8, "pencil")],
});
assert.equal(pair.left.inputType, "finger");

// Two check-ins with different measurements, and one measurement missing on the left hand
const left = rec("left", 10, "pencil", { spiral_duration: 0.5, spiral_mean_speed: 0.31, spiral_ldlj: 0.4, spiral_sparc: NaN });
const right = rec("right", 10, "pencil", { spiral_duration: 0.7, spiral_mean_speed: 0.68, spiral_ldlj: 0.3, spiral_sparc: 0.5 });
const rows = compareHands({ left, right });

// The rows go from biggest difference to smallest, and leave out the missing measurement
assert.deepEqual(keysOf(rows), ["spiral_mean_speed", "spiral_duration", "spiral_ldlj"]);

// Each row has the left value, the right value, and left minus right
assert.equal(rows[0].left, 0.31);
assert.equal(rows[0].right, 0.68);
assert.ok(Math.abs(rows[0].diff - -0.37) < 1e-9);
assert.ok(rows[2].diff > 0);

// With a set order, only the measurements in that order that both hands have are compared
assert.deepEqual(keysOf(compareHands({ left, right, order: ["spiral_ldlj", "spiral_tremor_4_6"] })), ["spiral_ldlj"]);

// With no measurements on one hand, there are no rows
assert.deepEqual(compareHands({ left: rec("left", 1), right }), []);

// Measurements with the same difference keep their normal order
const evenLeft = rec("left", 1, "pencil", { spiral_duration: 0.5, spiral_mean_speed: 0.25 });
const evenRight = rec("right", 1, "pencil", { spiral_duration: 0.75, spiral_mean_speed: 0 });
assert.deepEqual(keysOf(compareHands({ left: evenLeft, right: evenRight })), ["spiral_duration", "spiral_mean_speed"]);

console.log("HANDS OK");