// MEDS.JS DOES THE MATH FOR THE MEDICATION DIARY
// IT FINDS THE HOURS SINCE A DOSE, GROUPS CHECK-INS BY THOSE HOURS AND BUILDS THE DOSE TIMING SUMMARY
// THE FUNCTIONS ONLY USE WHAT THEY ARE GIVEN, SO THEY RUN IN THE BROWSER, IN NODE AND IN THE IPAD APP

// How many milliseconds are in an hour
const HOUR_MS = 3600000;

// How many check-ins with a logged dose are needed before the chart shows
export const MIN_CHECKINS = 6;


// Find the hours from the latest dose at or before ts
// Give back null if there is no dose, or if the latest one is more than maxHours ago
export function hoursSinceDose({ ts, doses, maxHours = 12 }) {

  // Check every dose, since the doses can be in any order
  let latest = null;
  for (const dose of doses) {
    if (dose.ts <= ts && (latest === null || dose.ts > latest)) {
      latest = dose.ts;
    }
  }

  if (latest === null) {
    return null;
  }

  // Turn the time since that dose into hours, and give back null if it was too long ago
  const hours = (ts - latest) / HOUR_MS;
  if (hours > maxHours) {
    return null;
  }
  return hours;
}


// Find the middle value of a list of numbers
function median(values) {

  // Sort a copy from smallest to largest
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);

  // An odd count has one middle value, and an even count averages the two in the middle
  if (sorted.length % 2) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}


// Group check-ins into bins by hours since a dose, with each bin's count and median for one measure
// edges are the hours where one bin ends and the next one starts
export function groupByHoursSinceDose({ checkins, doses, measure, edges = [0, 1, 2, 3, 4, 6, 12] }) {

  // Doses from before the last edge aren't counted
  const maxHours = edges[edges.length - 1];

  // Make one empty bin between each pair of edges
  const bins = [];
  for (let i = 0; i < edges.length - 1; i++) {
    bins.push({ from: edges[i], to: edges[i + 1], values: [] });
  }

  for (const checkin of checkins) {

    // Skip check-ins without a number for this measure
    const value = checkin.measurePct?.[measure];
    if (!Number.isFinite(value)) {
      continue;
    }

    // Skip check-ins with no dose in the hours before them
    const hours = hoursSinceDose({ ts: checkin.ts, doses, maxHours });
    if (hours === null) {
      continue;
    }

    // Find the bin these hours fall in, where only the last bin includes its upper edge
    let bin = null;
    for (let i = 0; i < bins.length; i++) {
      const last = i === bins.length - 1;
      if (hours >= bins[i].from && (hours < bins[i].to || last)) {
        bin = bins[i];
        break;
      }
    }

    if (bin) {
      bin.values.push(value);
    }
  }

  // Give back each bin's edges, how many check-ins it has and their median
  const result = [];
  for (const { from, to, values } of bins) {
    let middle = null;
    if (values.length) {
      middle = median(values);
    }
    result.push({ from, to, n: values.length, median: middle });
  }
  return result;
}


// Find the bin with the highest median among bins with at least minN check-ins
// Give back null if no bin has enough
export function highestBin({ bins, minN = 2 }) {
  let best = null;
  for (const bin of bins) {

    // Skip bins with too few check-ins or no median
    if (bin.n < minN || bin.median === null) {
      continue;
    }

    // Keep the higher median, and on a tie keep the first bin
    if (best === null || bin.median > best.median) {
      best = bin;
    }
  }
  return best;
}


// Build the dose timing summary for one measure
// ready is true once MIN_CHECKINS check-ins are counted and highestBin found a bin
export function doseTiming({ checkins, doses, measure, hand = null, inputType = null }) {

  // Only use check-ins with this hand and input, when they are given
  const same = [];
  for (const c of checkins) {
    const handOk = hand === null || c.hand === hand;
    const inputOk = inputType === null || c.inputType === inputType;
    if (handOk && inputOk) {
      same.push(c);
    }
  }

  // Group them by hours since a dose, and count how many landed in a bin
  const bins = groupByHoursSinceDose({ checkins: same, doses, measure });
  let counted = 0;
  for (const bin of bins) {
    counted += bin.n;
  }

  // Find the bin with the highest median, and check whether there is enough to show the chart
  const best = highestBin({ bins });
  const ready = counted >= MIN_CHECKINS && best !== null;

  return { ready, counted, bins, best };
}