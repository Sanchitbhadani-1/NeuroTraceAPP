// HANDS.JS COMPARES THE LEFT HAND WITH THE RIGHT HAND
// IT FINDS THE LATEST PAIR OF LEFT AND RIGHT CHECK-INS AND THE DIFFERENCE BETWEEN THEM ON EACH MEASURE

import { SPIRAL_FEATURE_ORDER } from "./nt-features.js";

// How many milliseconds are in a day
const DAY_MS = 86400000;


// Find the newest left and right check-in made with the same input, at most maxDaysApart days apart
// Give back null if there is no such pair
export function latestPair({ records, maxDaysApart = 7 }) {
  let best = null;

  for (const left of records) {

    // Only start from left hand check-ins
    if (left.hand !== "left") {
      continue;
    }

    for (const right of records) {

      // Only pair it with a right hand check-in made with the same input
      if (right.hand !== "right" || right.inputType !== left.inputType) {
        continue;
      }

      // Skip pairs drawn too many days apart
      if (Math.abs(left.ts - right.ts) > maxDaysApart * DAY_MS) {
        continue;
      }

      // Find which of the two check-ins came first and which came last
      const older = Math.min(left.ts, right.ts);
      const newer = Math.max(left.ts, right.ts);

      // Keep the most recent pair, judged by its older check-in, then by its newer one on a tie
      if (best === null || older > best.older || (older === best.older && newer > best.newer)) {
        best = { left, right, older, newer };
      }
    }
  }

  if (best === null) {
    return null;
  }
  return { left: best.left, right: best.right };
}


// Make one row per measure both hands have a number for, with diff as left minus right
// The biggest difference comes first, and equal differences keep the measure order
export function compareHands({ left, right, order = SPIRAL_FEATURE_ORDER }) {
  const rows = [];

  for (const key of order) {
    const l = left.measurePct?.[key];
    const r = right.measurePct?.[key];

    // Skip a measure unless both hands have a number for it
    if (!Number.isFinite(l) || !Number.isFinite(r)) {
      continue;
    }

    rows.push({ key, left: l, right: r, diff: l - r });
  }

  // Put the biggest difference first, whichever hand it favors
  rows.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
  return rows;
}