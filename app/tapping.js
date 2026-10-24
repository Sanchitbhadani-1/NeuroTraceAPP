// Retune on real ones, tuned on made-up curves
export const TAP_LOW = 0.2; // closed = below 20% of the gap range
export const TAP_HIGH = 0.4; // open = above 40%, kept low so shrinking taps still count
export const TRIM = 0.05; // range skips the top and bottom 5% of frames, so one wild frame can't stretch it
export const MAX_HOLE = 0.2; // seconds without a hand before frames on each side stop being joined
export const MIN_TAPS = 5; // fewer taps than this and the numbers say little
// A hand held still jitters by well under this, and a real tap opens by far more, so a smaller swing is read as no tapping
export const MIN_SWING = 0.25;

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

function quantile(xs, q) {
  const s = [...xs].sort((a, b) => a - b);
  const pos = q * (s.length - 1);
  const i = Math.floor(pos);
  return s[i] + (s[Math.ceil(pos)] - s[i]) * (pos - i);
}

function thirds(xs) {
  const k = Math.floor(xs.length / 3);
  return k ? [mean(xs.slice(0, k)), mean(xs.slice(-k))] : null;
}

// samples: [{ t: seconds since the first frame, gap: fingertip distance / hand size, or null }]
export function analyzeTaps({ samples = [] }) {
  // Split wherever the hand was missing too long, so no tap is guessed across a hole
  const segments = [];
  let last = null;
  for (const s of samples) {
    if (s.gap == null || !Number.isFinite(s.gap)) continue;
    if (!last || s.t - last.t > MAX_HOLE) segments.push([]);
    segments[segments.length - 1].push(s);
    last = s;
  }

  // 3-frame average, so a single glitchy frame can't look like a tap
  const smoothed = segments.map((seg) =>
    seg.map((s, i) => ({ t: s.t, gap: mean(seg.slice(Math.max(0, i - 1), i + 2).map((n) => n.gap)) }))
  );
  const gaps = smoothed.flat().map((s) => s.gap);
  const min = quantile(gaps, TRIM);
  const max = quantile(gaps, 1 - TRIM);
  const lo = min + TAP_LOW * (max - min);
  const hi = min + TAP_HIGH * (max - min);
  // No hand, or a still one, has no taps to find
  const moved = max - min >= MIN_SWING;

  // Two lines, not one, so wobble between them can't count twice
  // Tap time = lowest point of the dip, opening = highest point before it
  const tapTimes = [];
  const openings = [];
  for (const seg of moved ? smoothed : []) {
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

  const n = tapTimes.length;
  const intervals = tapTimes.slice(1).map((t, i) => t - tapTimes[i]);
  const duration = n >= 2 ? tapTimes[n - 1] - tapTimes[0] : null;
  const m = intervals.length ? mean(intervals) : null;
  const usual = intervals.length ? quantile(intervals, 0.5) : null;
  const opening = thirds(openings);
  const speed = thirds(intervals);

  return {
    counted: n >= MIN_TAPS,
    taps: n,
    duration,
    rate: duration ? intervals.length / duration : null, // gaps between taps per second, like training's tap_rate
    rhythmCv: intervals.length >= 2 ? Math.sqrt(mean(intervals.map((d) => (d - m) ** 2))) / m : null,
    meanOpening: n ? mean(openings) : null,
    openingChange: opening && opening[1] / opening[0] - 1, // last third vs first third, -0.18 = 18% smaller
    rateChange: speed && speed[0] / speed[1] - 1, // same for speed, negative = slowed down
    pauses: intervals.filter((d) => d > 2 * usual).length, // a gap over twice the usual one
    tapTimes,
    openings,
  };
}
