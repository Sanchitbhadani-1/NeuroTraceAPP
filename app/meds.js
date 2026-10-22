// pure functions for med diary, run in browser, Node, and iPad app

const HOUR_MS = 3600000;

export const MIN_CHECKINS = 6; // 6 check-ins until chart is displayed

// how many hours since last dose or null
export function hoursSinceDose({ ts, doses, maxHours = 12 }) {
  let latest = null;
  // find the latest dose
  for (const dose of doses) {
    if (dose.ts <= ts && (latest === null || dose.ts > latest)) latest = dose.ts;
  }
  if (latest === null) return null;
  const hours = (ts - latest) / HOUR_MS;
  return hours > maxHours ? null : hours;
}

// returns median of a list
function median(values) {
  // sort a copy so original order stays unchanged
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

// group check-in values by hours since last dose. return counts and medians.
export function groupByHoursSinceDose({ checkins, doses, measure, edges = [0, 1, 2, 3, 4, 6, 12] }) {
  const maxHours = edges[edges.length - 1];
  const bins = edges.slice(0, -1).map((from, i) => ({ from, to: edges[i + 1], values: [] }));
  for (const checkin of checkins) {
    const value = checkin.measurePct?.[measure];
    // skip misisng or invalid values
    if (!Number.isFinite(value)) continue;
    const hours = hoursSinceDose({ ts: checkin.ts, doses, maxHours });
    if (hours === null) continue;
    // upper edge only in the last bin
    const bin = bins.find((b, i) => hours >= b.from && (hours < b.to || i === bins.length - 1));
    if (bin) bin.values.push(value);
  }
  return bins.map(({ from, to, values }) => ({
    from,
    to,
    n: values.length,
    median: values.length ? median(values) : null,
  }));
}

// find the highest median of bins with enough check-ins
export function highestBin({ bins, minN = 2 }) {
  let best = null;
  for (const bin of bins) {
    if (bin.n < minN || bin.median === null) continue;
    // if medians tie, keep the first bin
    if (best === null || bin.median > best.median) best = bin;
  }
  return best;
}

// build the dose timing summary. check if enough data is available.
export function doseTiming({ checkins, doses, measure, hand = null, inputType = null }) {
  // filter by hand and input type if asked
  const same = checkins.filter(
    (c) => (hand === null || c.hand === hand) && (inputType === null || c.inputType === inputType),
  );
  const bins = groupByHoursSinceDose({ checkins: same, doses, measure });
  const counted = bins.reduce((sum, bin) => sum + bin.n, 0);
  const best = highestBin({ bins });
  return { ready: counted >= MIN_CHECKINS && best !== null, counted, bins, best };
}