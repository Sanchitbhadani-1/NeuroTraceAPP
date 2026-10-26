// MEDS-CHECK.MJS TESTS MEDS.JS ON MADE UP CHECK-INS AND DOSES
// IT CHECKS THE HOURS SINCE A DOSE, HOW CHECK-INS ARE GROUPED BY THAT TIME, AND WHEN THE DOSE TIMING CHART IS READY
// RUN IT FROM THE REPO FOLDER WITH node app/tools/meds-check.mjs

import assert from "node:assert/strict";
import { hoursSinceDose, groupByHoursSinceDose, highestBin, doseTiming, MIN_CHECKINS } from "../meds.js";

// One hour in milliseconds
const H = 3600000;

// The measurement every made up check-in has
const SPEED = "spiral_mean_speed";

// One dose at the very start
const doses = [{ ts: 0 }];


// Make a made up check-in some hours after the dose, with a speed value, a hand and an input
function checkin(hours, value, hand = "right", inputType = "pencil") {
  return { ts: hours * H, hand, inputType, measurePct: { [SPEED]: value } };
}


// Get the start and end hour of each bin, in order
function edgesOf(bins) {
  const edges = [];
  for (const b of bins) {
    edges.push([b.from, b.to]);
  }
  return edges;
}


// Get how many check-ins are in each bin, in order
function countsOf(bins) {
  const counts = [];
  for (const b of bins) {
    counts.push(b.n);
  }
  return counts;
}


// The latest dose at or before the check-in is used, even when the doses are out of order
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 8 * H }] }), 2);
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 7 * H }, { ts: 11 * H }, { ts: 9 * H }] }), 1);

// A dose after the check-in, or no dose at all, gives no answer
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 11 * H }] }), null);
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [] }), null);

// A dose more than 12 hours before doesn't count, and exactly 12 hours does
assert.equal(hoursSinceDose({ ts: 25 * H, doses: [{ ts: 12 * H }] }), null);
assert.equal(hoursSinceDose({ ts: 24 * H, doses: [{ ts: 12 * H }] }), 12);

// A dose at the same time as the check-in is 0 hours
assert.equal(hoursSinceDose({ ts: 10 * H, doses: [{ ts: 10 * H }] }), 0);

// Group made up check-ins by hours since the dose
// Two of them have no speed value, and one is more than 12 hours after the dose
const bins = groupByHoursSinceDose({
  checkins: [
    checkin(0.5, 0.2),
    checkin(1.5, 0.4),
    checkin(1.7, 0.6),
    checkin(12, 0.9),
    checkin(13, 0.5),
    { ts: 3 * H, measurePct: {} },
    { ts: 3 * H, measurePct: { [SPEED]: NaN } },
  ],
  doses,
  measure: SPEED,
});

// There are six bins, from 0 to 12 hours
assert.equal(bins.length, 6);
assert.deepEqual(edgesOf(bins), [[0, 1], [1, 2], [2, 3], [3, 4], [4, 6], [6, 12]]);

// Check-ins with no value or more than 12 hours after are left out, and exactly 12 hours lands in the last bin
assert.deepEqual(countsOf(bins), [1, 2, 0, 0, 0, 1]);

// A bin with two check-ins takes the average of the two, and an empty bin has no median
assert.equal(bins[1].median, 0.5);
assert.equal(bins[2].median, null);

// A bin with an odd number of check-ins takes the middle value
const odd = groupByHoursSinceDose({
  checkins: [checkin(1.5, 0.9), checkin(1.5, 0.1), checkin(1.5, 0.25)],
  doses,
  measure: SPEED,
});
assert.equal(odd[1].median, 0.25);

// The bin with the highest median wins
assert.equal(highestBin({ bins }).from, 1);

// A bin with only 1 check-in can't win, even with the highest value
const lucky = groupByHoursSinceDose({
  checkins: [checkin(0.5, 0.9), checkin(1.5, 0.1), checkin(1.6, 0.2)],
  doses,
  measure: SPEED,
});
assert.equal(highestBin({ bins: lucky }).from, 1);

// With no bin that has at least 2 check-ins, there's no highest bin
const single = groupByHoursSinceDose({ checkins: [checkin(0.5, 0.9)], doses, measure: SPEED });
assert.equal(highestBin({ bins: single }), null);

// When two bins tie, the earlier one wins
const tie = groupByHoursSinceDose({
  checkins: [checkin(0.2, 0.5), checkin(0.4, 0.5), checkin(1.2, 0.5), checkin(1.4, 0.5)],
  doses,
  measure: SPEED,
});
assert.equal(highestBin({ bins: tie }).from, 0);

// Five right hand check-ins, one short of what the chart needs
const five = [checkin(1.1, 0.5), checkin(1.2, 0.5), checkin(2.1, 0.4), checkin(2.2, 0.4), checkin(5, 0.3)];

// The chart needs 6 check-ins, and 5 isn't enough
assert.equal(MIN_CHECKINS, 6);
assert.equal(doseTiming({ checkins: five, doses, measure: SPEED, hand: "right" }).ready, false);

// With a sixth check-in the chart is ready, and the 1 to 2 hour bin is the highest
const timing = doseTiming({ checkins: [...five, checkin(5.5, 0.3)], doses, measure: SPEED, hand: "right" });
assert.equal(timing.ready, true);
assert.equal(timing.counted, 6);
assert.equal(timing.best.from, 1);

// A left hand check-in is left out when only the right hand is asked for
const withLeft = [...five, checkin(5.5, 0.3, "left")];
assert.equal(doseTiming({ checkins: withLeft, doses, measure: SPEED, hand: "right" }).counted, 5);

// A finger check-in is left out when only the Pencil is asked for
const withFinger = [...five, checkin(5.5, 0.3, "right", "finger")];
assert.equal(doseTiming({ checkins: withFinger, doses, measure: SPEED, inputType: "pencil" }).counted, 5);

// With no hand asked for, every check-in counts
assert.equal(doseTiming({ checkins: withLeft, doses, measure: SPEED }).counted, 6);

console.log("MEDS OK");