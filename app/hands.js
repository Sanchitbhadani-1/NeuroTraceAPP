import { SPIRAL_FEATURE_ORDER } from "./nt-features.js";

const DAY_MS = 86400000;

// find a left/right pair with the same input type (at max maxDaysApart days apart)
export function latestPair({ records, maxDaysApart = 7 }) {
  let best = null;
  for (const left of records) {
    if (left.hand !== "left") continue;
    for (const right of records) {
      // match opposite hands with same input type
      if (right.hand !== "right" || right.inputType !== left.inputType) continue;
      if (Math.abs(left.ts - right.ts) > maxDaysApart * DAY_MS) continue;
      const older = Math.min(left.ts, right.ts);
      const newer = Math.max(left.ts, right.ts);
      // prefer the newest old check-in. measure the newest new one.
      if (best === null || older > best.older || (older === best.older && newer > best.newer)) {
        best = { left, right, older, newer };
      }
    }
  }
  return best && { left: best.left, right: best.right };
}

// compare percentiles for each measure. diff = left - right.
export function compareHands({ left, right, order = SPIRAL_FEATURE_ORDER }) {
  return order
    // only compare measures with valid numbers for both hands
    .filter((key) => Number.isFinite(left.measurePct?.[key]) && Number.isFinite(right.measurePct?.[key]))
    .map((key) => {
      const l = left.measurePct[key];
      const r = right.measurePct[key];
      return { key, left: l, right: r, diff: l - r };
    })
    // largest absolute difference first
    .sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
}
