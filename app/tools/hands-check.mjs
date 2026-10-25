// Assert-based check for hands.js on made-up check-ins. Run from the repo root:
//   node app/tools/hands-check.mjs

import assert from "node:assert/strict";
import { latestPair, compareHands } from "../hands.js";

const DAY = 86400000;
const rec = (hand, day, inputType = "pencil", measurePct = {}) => ({ ts: day * DAY, hand, inputType, measurePct });

assert.equal(latestPair({ records: [] }), null);
assert.equal(latestPair({ records: [rec("left", 10), rec("left", 9)] }), null);
// No pair without both hands

let pair = latestPair({ records: [rec("left", 10), rec("right", 9)] });
assert.equal(pair.left.ts, 10 * DAY);
assert.equal(pair.right.ts, 9 * DAY);
// A left and a right check-in a day apart pair up

assert.equal(latestPair({ records: [rec("left", 10, "pencil"), rec("right", 9, "finger")] }), null);
assert.equal(latestPair({ records: [rec("left", 20), rec("right", 12)] }), null);
assert.notEqual(latestPair({ records: [rec("left", 19), rec("right", 12)] }), null);
// Different inputs or more than 7 days apart don't pair, exactly 7 does

pair = latestPair({ records: [rec("left", 18), rec("left", 16), rec("right", 15), rec("right", 12)] });
assert.equal(pair.left.ts, 18 * DAY);
assert.equal(pair.right.ts, 15 * DAY);

pair = latestPair({ records: [rec("left", 18), rec("left", 16), rec("right", 16), rec("right", 3), rec("left", 2)] });
assert.equal(pair.left.ts, 18 * DAY);
assert.equal(pair.right.ts, 16 * DAY);
// The pair whose older check-in is newest wins, then the newer one

pair = latestPair({ records: [rec("right", 1), rec("left", 2), rec("left", 3)] });
assert.equal(pair.left.ts, 3 * DAY);
// Record order doesn't matter

pair = latestPair({
  records: [rec("left", 10, "finger"), rec("right", 10, "finger"), rec("left", 8, "pencil"), rec("right", 8, "pencil")],
});
assert.equal(pair.left.inputType, "finger");
// Pencil pairs and finger pairs are found separately, the newest wins

const left = rec("left", 10, "pencil", { spiral_duration: 0.5, spiral_mean_speed: 0.31, spiral_ldlj: 0.4, spiral_sparc: NaN });
const right = rec("right", 10, "pencil", { spiral_duration: 0.7, spiral_mean_speed: 0.68, spiral_ldlj: 0.3, spiral_sparc: 0.5 });
const rows = compareHands({ left, right });
assert.deepEqual(rows.map((r) => r.key), ["spiral_mean_speed", "spiral_duration", "spiral_ldlj"]);
assert.equal(rows[0].left, 0.31);
assert.equal(rows[0].right, 0.68);
assert.ok(Math.abs(rows[0].diff - -0.37) < 1e-9);
assert.ok(rows[2].diff > 0);
assert.deepEqual(compareHands({ left, right, order: ["spiral_ldlj", "spiral_tremor_4_6"] }).map((r) => r.key), ["spiral_ldlj"]);
assert.deepEqual(compareHands({ left: rec("left", 1), right }), []);
// Biggest difference first, measures missing on either hand left out

const evenLeft = rec("left", 1, "pencil", { spiral_duration: 0.5, spiral_mean_speed: 0.25 });
const evenRight = rec("right", 1, "pencil", { spiral_duration: 0.75, spiral_mean_speed: 0 });
assert.deepEqual(compareHands({ left: evenLeft, right: evenRight }).map((r) => r.key), ["spiral_duration", "spiral_mean_speed"]);
// Equal differences keep the measure order

console.log("HANDS OK");
