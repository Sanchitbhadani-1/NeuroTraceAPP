// Assert-based check for meds.js on made-up check-ins and doses. Run from the repo root:
//   node app/tools/meds-check.mjs

import assert from "node:assert/strict";
import { hoursSinceDose, groupByHoursSinceDose, highestBin, doseTiming, MIN_CHECKINS } from "../meds.js";

const H = 3600000;
const SPEED = "spiral_mean_speed";
const doses = [{ ts: 0 }];
const checkin = (hours, value, hand = "right", inputType = "pencil") =>
  ({ ts: hours * H, hand, inputType, measurePct: { [SPEED]: value } });

assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 8 * H }] }), 2);
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 7 * H }, { ts: 11 * H }, { ts: 9 * H }] }), 1);
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 11 * H }] }), null);
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [] }), null);
assert.equal(hoursSinceDose({ ts: 25 * H, doses: [{ ts: 12 * H }] }), null);
assert.equal(hoursSinceDose({ ts: 24 * H, doses: [{ ts: 12 * H }] }), 12);
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 10 * H }] }), 0);
// Uses the latest dose at or before the check-in, within 12 hours

const bins = groupByHoursSinceDose({
  checkins: [checkin(0.5, 0.2), checkin(1.5, 0.4), checkin(1.7, 0.6), checkin(12, 0.9), checkin(13, 0.5),
    { ts: 3 * H, measurePct: {} }, { ts: 3 * H, measurePct: { [SPEED]: NaN } }],
  doses,
  measure: SPEED,
});
assert.equal(bins.length, 6);
assert.deepEqual(bins.map((b) => [b.from, b.to]), [[0, 1], [1, 2], [2, 3], [3, 4], [4, 6], [6, 12]]);
assert.deepEqual(bins.map((b) => b.n), [1, 2, 0, 0, 0, 1]);
assert.equal(bins[1].median, 0.5);
assert.equal(bins[2].median, null);
// Six bins - check-ins missing the measure, NaN, or over 12 hours after the dose are left out

const odd = groupByHoursSinceDose({ checkins: [checkin(1.5, 0.9), checkin(1.5, 0.1), checkin(1.5, 0.25)], doses, measure: SPEED });
assert.equal(odd[1].median, 0.25);
// An odd count takes the middle value

assert.equal(highestBin({ bins }).from, 1);
const lucky = groupByHoursSinceDose({ checkins: [checkin(0.5, 0.9), checkin(1.5, 0.1), checkin(1.6, 0.2)], doses, measure: SPEED });
assert.equal(highestBin({ bins: lucky }).from, 1);
assert.equal(highestBin({ bins: groupByHoursSinceDose({ checkins: [checkin(0.5, 0.9)], doses, measure: SPEED }) }), null);
const tie = groupByHoursSinceDose({ checkins: [checkin(0.2, 0.5), checkin(0.4, 0.5), checkin(1.2, 0.5), checkin(1.4, 0.5)], doses, measure: SPEED });
assert.equal(highestBin({ bins: tie }).from, 0);
// A bin with 1 check-in can't win, a tie keeps the earlier bin

const five = [checkin(1.1, 0.5), checkin(1.2, 0.5), checkin(2.1, 0.4), checkin(2.2, 0.4), checkin(5, 0.3)];
assert.equal(MIN_CHECKINS, 6);
assert.equal(doseTiming({ checkins: five, doses, measure: SPEED, hand: "right" }).ready, false);
const timing = doseTiming({ checkins: [...five, checkin(5.5, 0.3)], doses, measure: SPEED, hand: "right" });
assert.equal(timing.ready, true);
assert.equal(timing.counted, 6);
assert.equal(timing.best.from, 1);
assert.equal(doseTiming({ checkins: [...five, checkin(5.5, 0.3, "left")], doses, measure: SPEED, hand: "right" }).counted, 5);
assert.equal(doseTiming({ checkins: [...five, checkin(5.5, 0.3, "right", "finger")], doses, measure: SPEED, inputType: "pencil" }).counted, 5);
assert.equal(doseTiming({ checkins: [...five, checkin(5.5, 0.3, "left")], doses, measure: SPEED }).counted, 6);
// Ready at 6 check-ins, other hands and inputs filtered out when asked

console.log("MEDS OK");
