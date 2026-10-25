// Left vs right hand comparison - the latest pair of check-ins and the difference on each measure

import { SPIRAL_FEATURE_ORDER } from "./nt-features.js";

const DAY_MS = 86400000;

// Newest left and right check-in with the same input, at most maxDaysApart days apart, or null
export function latestPair({ records, maxDaysApart = 7 }) {
  let best = null;
  for (const left of records) {
    if (left.hand !== "left") continue;
    for (const right of records) {
      if (right.hand !== "right" || right.inputType !== left.inputType) continue;
      // Only pairs matching input types
      if (Math.abs(left.ts - right.ts) > maxDaysApart * DAY_MS) continue;
      const older = Math.min(left.ts, right.ts);
      const newer = Math.max(left.ts, right.ts);
      if (best === null || older > best.older || (older === best.older && newer > best.newer)) {
        best = { left, right, older, newer };
      }
      // Keeps the most recent pair - judged by its older check-in, then by its newer one on a tie
    }
  }
  if (best === null) return null;
  return { left: best.left, right: best.right };
}

// One row per measure both hands have a number for, diff = left - right, biggest difference first
export function compareHands({ left, right, order = SPIRAL_FEATURE_ORDER }) {
  return order
    .filter((key) => {
      const l = left.measurePct?.[key];
      const r = right.measurePct?.[key];
      return Number.isFinite(l) && Number.isFinite(r);
    })
    .map((key) => {
      const l = left.measurePct[key];
      const r = right.measurePct[key];
      return { key, left: l, right: r, diff: l - r };
    })
    .sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
  // Equal differences keep the measure order
}
