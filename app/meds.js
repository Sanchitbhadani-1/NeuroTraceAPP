// Medication diary math - hours since a dose, check-ins grouped by that time and the dose-timing summary
// Pure functions. They run in the browser, in Node and in the iPad app

const HOUR_MS = 3600000;

export const MIN_CHECKINS = 6;
// Check-ins with a logged dose needed before the chart shows

// Hours from the latest dose at or before ts, or null if there's none within maxHours
export function hoursSinceDose({ ts, doses, maxHours = 12 }) {
  let latest = null;
  for (const dose of doses) {
    if (dose.ts <= ts && (latest === null || dose.ts > latest)) {
      latest = dose.ts;
    }
  }
  // Checks every dose - the doses can be in any order
  if (latest === null) return null;
  const hours = (ts - latest) / HOUR_MS;
  return hours > maxHours ? null : hours;
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

// Groups check-ins into hours-since-dose bins, with each bin's count and median for one measure
export function groupByHoursSinceDose({ checkins, doses, measure, edges = [0, 1, 2, 3, 4, 6, 12] }) {
  const maxHours = edges[edges.length - 1];
  const bins = edges.slice(0, -1).map((from, i) => ({ from, to: edges[i + 1], values: [] }));
  for (const checkin of checkins) {
    const value = checkin.measurePct?.[measure];
    if (!Number.isFinite(value)) continue;
    const hours = hoursSinceDose({ ts: checkin.ts, doses, maxHours });
    if (hours === null) continue;
    const bin = bins.find((b, i) => {
      const last = i === bins.length - 1;
      return hours >= b.from && (hours < b.to || last);
    });
    // Only the last bin includes its upper edge
    if (bin) bin.values.push(value);
  }
  return bins.map(({ from, to, values }) => ({
    from,
    to,
    n: values.length,
    median: values.length ? median(values) : null,
  }));
}

// The bin with the highest median among bins with at least minN check-ins, or null
export function highestBin({ bins, minN = 2 }) {
  let best = null;
  for (const bin of bins) {
    if (bin.n < minN || bin.median === null) continue;
    if (best === null || bin.median > best.median) {
      best = bin;
    }
    // Ties keep the first bin
  }
  return best;
}

// Builds the dose-timing summary
export function doseTiming({ checkins, doses, measure, hand = null, inputType = null }) {
  const same = checkins.filter((c) => {
    const handOk = hand === null || c.hand === hand;
    const inputOk = inputType === null || c.inputType === inputType;
    return handOk && inputOk;
  });
  // Only check-ins with this hand and input, when given
  const bins = groupByHoursSinceDose({ checkins: same, doses, measure });
  const counted = bins.reduce((sum, bin) => sum + bin.n, 0);
  const best = highestBin({ bins });
  const ready = counted >= MIN_CHECKINS && best !== null;
  return { ready, counted, bins, best };
}