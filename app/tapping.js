// TAPPING.JS FINDS FINGER TAPS IN THE CAMERA FRAMES
// IT TAKES THE GAP BETWEEN THE FINGERTIPS IN EACH FRAME AND MEASURES THE TAPS, HOW WIDE THE FINGERS OPENED AND HOW STEADY THE RHYTHM WAS
// THE NUMBERS WERE TUNED ON MADE UP CURVES AND STILL NEED RETUNING ON REAL ONES

// Closed means the gap is below 20% of its range
export const TAP_LOW = 0.2;

// Open means the gap is above 40% of its range, kept low so taps that shrink still count
export const TAP_HIGH = 0.4;

// The range skips the top and bottom 5% of frames, so one wild frame can't stretch it
export const TRIM = 0.05;

// Seconds without a hand before the frames on each side stop being joined
export const MAX_HOLE = 0.2;

// With fewer taps than this the numbers say little
export const MIN_TAPS = 5;

// A hand held still jitters by well under this, and a real tap opens by far more, so a smaller swing is read as no tapping
export const MIN_SWING = 0.25;


// Find the average of a list of numbers
function mean(xs) {
  let total = 0;
  for (const x of xs) {
    total += x;
  }
  return total / xs.length;
}


// Find the value a share q of the way through the numbers once they are sorted, going between the two nearest ones
function quantile(xs, q) {
  const s = [...xs].sort((a, b) => a - b);
  const pos = q * (s.length - 1);
  const i = Math.floor(pos);
  return s[i] + (s[Math.ceil(pos)] - s[i]) * (pos - i);
}


// Find the average of the first third and of the last third, or null with fewer than 3 numbers
function thirds(xs) {
  const k = Math.floor(xs.length / 3);
  if (!k) {
    return null;
  }
  return [mean(xs.slice(0, k)), mean(xs.slice(-k))];
}


// Find and measure the taps in a recording
// samples is a list of { t, gap }, where t is seconds since the first frame and gap is the fingertip distance over the hand's size, or null
export function analyzeTaps({ samples = [] }) {

  // Split wherever the hand was missing too long, so no tap is guessed across a hole
  const segments = [];
  let last = null;
  for (const s of samples) {
    if (s.gap == null || !Number.isFinite(s.gap)) {
      continue;
    }
    if (!last || s.t - last.t > MAX_HOLE) {
      segments.push([]);
    }
    segments[segments.length - 1].push(s);
    last = s;
  }

  // Average each frame with the one on each side, so a single glitchy frame can't look like a tap
  const smoothed = [];
  for (const seg of segments) {
    const out = [];
    for (let i = 0; i < seg.length; i++) {
      const around = [];
      for (const s of seg.slice(Math.max(0, i - 1), i + 2)) {
        around.push(s.gap);
      }
      out.push({ t: seg[i].t, gap: mean(around) });
    }
    smoothed.push(out);
  }

  // Find the range of the gap without its very top and bottom frames, and the closed and open lines inside it
  const gaps = [];
  for (const seg of smoothed) {
    for (const s of seg) {
      gaps.push(s.gap);
    }
  }
  const min = quantile(gaps, TRIM);
  const max = quantile(gaps, 1 - TRIM);
  const lo = min + TAP_LOW * (max - min);
  const hi = min + TAP_HIGH * (max - min);

  // No hand, or a still one, has no taps to find
  const moved = max - min >= MIN_SWING;
  let toSearch = [];
  if (moved) {
    toSearch = smoothed;
  }

  // Use two lines instead of one, so wobble between them can't count twice
  // A tap's time is the lowest point of its dip, and its opening is the highest point before it
  const tapTimes = [];
  const openings = [];
  for (const seg of toSearch) {
    let state = "start";
    let peak = 0;
    let valley = null;
    for (const s of seg) {
      if (s.gap > hi) {

        // Opening again after a dip finishes that tap
        if (state === "closed") {
          tapTimes.push(valley.t);
        }

        // Keep the highest point of this opening
        if (state === "open") {
          peak = Math.max(peak, s.gap);
        } else {
          peak = s.gap;
        }
        state = "open";
      } else if (s.gap < lo) {

        // Closing after an opening starts a dip, and the dip keeps its lowest point
        if (state === "open") {
          openings.push(peak);
          valley = s;
          state = "closed";
        } else if (state === "closed" && s.gap < valley.gap) {
          valley = s;
        }
      }
    }

    // A dip at the end of the recording still counts as a tap
    if (state === "closed") {
      tapTimes.push(valley.t);
    }
  }

  // The time between each tap and the next
  const n = tapTimes.length;
  const intervals = [];
  for (let i = 1; i < n; i++) {
    intervals.push(tapTimes[i] - tapTimes[i - 1]);
  }

  // The time from the first tap to the last
  let duration = null;
  if (n >= 2) {
    duration = tapTimes[n - 1] - tapTimes[0];
  }

  // The average and the normal time between taps, where normal is the median
  let m = null;
  let normal = null;
  if (intervals.length) {
    m = mean(intervals);
    normal = quantile(intervals, 0.5);
  }

  // Gaps between taps per second, the same as tap_rate in the training scripts
  let rate = null;
  if (duration) {
    rate = intervals.length / duration;
  }

  // How much the time between taps varies, as a share of the average
  let rhythmCv = null;
  if (intervals.length >= 2) {
    const squares = [];
    for (const d of intervals) {
      squares.push((d - m) ** 2);
    }
    rhythmCv = Math.sqrt(mean(squares)) / m;
  }

  // The average opening
  let meanOpening = null;
  if (n) {
    meanOpening = mean(openings);
  }

  // The last third of the openings against the first third, so -0.18 means 18% smaller
  const opening = thirds(openings);
  let openingChange = null;
  if (opening) {
    openingChange = opening[1] / opening[0] - 1;
  }

  // The same for speed, where below 0 means the taps slowed down
  const speed = thirds(intervals);
  let rateChange = null;
  if (speed) {
    rateChange = speed[0] / speed[1] - 1;
  }

  // Count the pauses, where a gap is more than twice the normal one
  let pauses = 0;
  for (const d of intervals) {
    if (d > 2 * normal) {
      pauses++;
    }
  }

  return {
    counted: n >= MIN_TAPS,
    taps: n,
    duration,
    rate,
    rhythmCv,
    meanOpening,
    openingChange,
    rateChange,
    pauses,
    tapTimes,
    openings,
  };
}