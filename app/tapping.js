export const TAP_LOW = 0.2;
export const TAP_HIGH = 0.4;
export const MAX_HOLE = 0.2;
export const MIN_TAPS = 5;

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

function median(xs) {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function thirds(xs) {
  const k = Math.floor(xs.length / 3);
  return k ? [mean(xs.slice(0, k)), mean(xs.slice(-k))] : null;
}

export function analyzeTaps({ samples }) {
  // Segments
  const segments = [];
  let last = null;
  for (const s of samples) {
    if (s.gap == null || !Number.isFinite(s.gap)) continue;
    if (!last || s.t - last.t > MAX_HOLE) segments.push([]);
    segments[segments.length - 1].push(s);
    last = s;
  }

  // Smooth
  const smoothed = segments.map((seg) =>
    seg.map((s, i) => ({ t: s.t, gap: mean(seg.slice(Math.max(0, i - 1), i + 2).map((n) => n.gap)) }))
  );
  const gaps = smoothed.flat().map((s) => s.gap);
  const min = gaps.reduce((a, b) => Math.min(a, b), Infinity);
  const max = gaps.reduce((a, b) => Math.max(a, b), -Infinity);
  const lo = min + TAP_LOW * (max - min);
  const hi = min + TAP_HIGH * (max - min);

  // Count taps: two thresholds so jitter in the middle can't count twice
  const tapTimes = [];
  const openings = [];
  for (const seg of smoothed) {
    let state = "start";
    let peak = 0;
    let valley = null;
    for (const s of seg) {
      if (s.gap > hi) {
        if (state === "closed") tapTimes.push(valley.t);
        peak = state === "open" ? Math.max(peak, s.gap) : s.gap;
        state = "open";
      } else if (s.gap < lo) {
        if (state === "open") {
          openings.push(peak);
          valley = s;
          state = "closed";
        } else if (state === "closed" && s.gap < valley.gap) {
          valley = s;
        }
      }
    }
    if (state === "closed") tapTimes.push(valley.t);
  }

  // Summary
  const n = tapTimes.length;
  const intervals = tapTimes.slice(1).map((t, i) => t - tapTimes[i]);
  const duration = n >= 2 ? tapTimes[n - 1] - tapTimes[0] : null;
  const m = intervals.length ? mean(intervals) : null;
  const opening = thirds(openings);
  const speed = thirds(intervals);

  return {
    counted: n >= MIN_TAPS,
    taps: n,
    duration,
    rate: duration ? intervals.length / duration : null,
    rhythmCv: intervals.length >= 2 ? Math.sqrt(mean(intervals.map((d) => (d - m) ** 2))) / m : null,
    meanOpening: n ? mean(openings) : null,
    openingChange: opening && opening[1] / opening[0] - 1,
    rateChange: speed && speed[0] / speed[1] - 1,
    pauses: intervals.filter((d) => d > 2 * median(intervals)).length,
    tapTimes,
    openings,
  };
}
