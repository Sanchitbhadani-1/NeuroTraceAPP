// The NeuroTrace feature pipeline in JavaScript.
// Mirrors training/neurotrace/preprocess.py and features.py function for
// function. THE ORDER IN preprocessTrace IS THE CONTRACT - it must match the
// Python or the model sees different numbers than it was trained on.
// Spiral only for v1: writing and tapping are not ported yet.

import { mean, maxOf, median, hypot, arange, interp, unwrap, gradient, lstsq, fftMag } from "./nt-signal.js";
import { butter, filtfilt, welch } from "./nt-filters.js";

// KEY ORDER = featureOrder in model.json. Append only.
export const SPIRAL_FEATURE_ORDER = [
  "spiral_duration",
  "spiral_max_deviation", "spiral_mean_deviation", "spiral_std_deviation",
  "spiral_major_reversals",
  "spiral_mean_speed", "spiral_std_speed",
  "spiral_ldlj", "spiral_sparc",
  "spiral_tremor_4_6", "spiral_tremor_6_12", "spiral_tremor_dominant_hz",
];

const std = (v) => { const m = mean(v); return Math.sqrt(mean(Array.from(v, (n) => (n - m) ** 2))); };

// --- preprocess ------------------------------------------------------

export function clean(t, x, y) {
  const kt = [], kx = [], ky = [];
  let runningMax = -Infinity;
  for (let i = 0; i < t.length; i++) {
    if (!Number.isFinite(t[i]) || !Number.isFinite(x[i]) || !Number.isFinite(y[i])) continue;
    // isFinite catches inf as well as NaN

    if (kt.length === 0 || t[i] > runningMax) {
      kt.push(t[i]); kx.push(x[i]); ky.push(y[i]);
      runningMax = Math.max(runningMax, t[i]);
      // Compare against the biggest timestamp KEPT so far, not the previous
      // sample - otherwise one wild timestamp throws away everything after it
    }
  }
  return [Float64Array.from(kt), Float64Array.from(kx), Float64Array.from(ky)];
}

export function trimStationary(t, x, y, threshold = 0.05, window = 10) {
  if (t.length <= window + 1) return [t, x, y];

  const n = t.length - window;
  const speed = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    speed[i] = Math.hypot(x[i + window] - x[i], y[i + window] - y[i]) / (t[i + window] - t[i]);
    // Displacement over a WINDOW, not one sample. Sensor jitter on a resting
    // pen reads as ~15% of drawing speed at window = 1, and no threshold works
  }

  const cut = threshold * median(speed);
  let first = -1, last = -1;
  for (let i = 0; i < n; i++) if (speed[i] > cut) { if (first < 0) first = i; last = i; }
  if (first < 0) return [t, x, y];

  const lo = first, hi = Math.min(t.length - 1, last + window);
  return [t.slice(lo, hi + 1), x.slice(lo, hi + 1), y.slice(lo, hi + 1)];
  // Pauses in the MIDDLE are kept - they are signal
}

export function resampleUniform(t, x, y, fs = 100.0) {
  for (let i = 1; i < t.length; i++) {
    if (t[i] <= t[i - 1]) throw new Error("timestamps must be strictly increasing");
  }
  const grid = arange(t[0], t[t.length - 1], 1.0 / fs);
  return [grid, interp(grid, t, x), interp(grid, t, y)];
}

export function normalize(x, y) {
  const mx = mean(x), my = mean(y);
  const cx = Float64Array.from(x, (v) => v - mx);
  const cy = Float64Array.from(y, (v) => v - my);
  let s = 0;
  for (let i = 0; i < cx.length; i++) s += cx[i] * cx[i] + cy[i] * cy[i];
  const scale = Math.sqrt(s / cx.length);
  return [Float64Array.from(cx, (v) => v / scale), Float64Array.from(cy, (v) => v / scale)];
}

export function lowPass(t, x, y, fs = 100.0, cutoff = 15.0, order = 4) {
  const { b, a } = butter(order, cutoff, fs, "low");
  if (x.length <= 3 * Math.max(a.length, b.length)) {
    throw new Error(`trace too short to filter (${x.length} samples)`);
  }
  return [t, filtfilt(b, a, x), filtfilt(b, a, y)];
}

export function preprocessTrace(t, x, y, fs = 100.0, cutoff = 15.0, trim = true) {
  [t, x, y] = clean(t, x, y);
  if (trim) [t, x, y] = trimStationary(t, x, y);
  [t, x, y] = resampleUniform(t, x, y, fs);
  [x, y] = normalize(x, y);
  return lowPass(t, x, y, fs, cutoff);
}

// --- spiral geometry -------------------------------------------------

export function spiralFitResidual(x, y, minTurns = 1.0) {
  const theta = unwrap(Float64Array.from(x, (v, i) => Math.atan2(y[i], v)));
  const r = hypot(x, y);

  const span = Math.abs(theta[theta.length - 1] - theta[0]) / (2 * Math.PI);
  if (span < minTurns) throw new Error(`trace covers only ${span.toFixed(2)} turns, too little to fit a spiral`);

  const ones = new Float64Array(theta.length).fill(1);
  const cos = Float64Array.from(theta, Math.cos);
  const sin = Float64Array.from(theta, Math.sin);
  const p = lstsq([ones, theta, cos, sin], r);
  // Columns 1 and 2 are the spiral itself; 3 and 4 soak up a wrong centre

  return Float64Array.from(r, (v, i) => v - (p[0] + p[1] * theta[i] + p[2] * cos[i] + p[3] * sin[i]));
}

export function majorRadiusReversals(x, y, minRetrace = 0.10) {
  const r = hypot(x, y);
  let count = 0, direction = 0, extreme = r[0];
  for (let i = 0; i < r.length; i++) {
    const v = r[i];
    if (direction === 0) {
      if (v > extreme + minRetrace) { direction = 1; extreme = v; }
      else if (v < extreme - minRetrace) { direction = -1; extreme = v; }
    } else if (direction === 1) {
      if (v > extreme) extreme = v;
      else if (v < extreme - minRetrace) { count++; direction = -1; extreme = v; }
    } else {
      if (v < extreme) extreme = v;
      else if (v > extreme + minRetrace) { count++; direction = 1; extreme = v; }
    }
  }
  return count;
}

export function deviationFeatures(d) {
  const abs = Float64Array.from(d, Math.abs);
  return {
    max_deviation: maxOf(abs),
    mean_deviation: mean(abs),
    std_deviation: std(d),
  };
}

// --- kinematics ------------------------------------------------------

export function kinematics(t, x, y) {
  const vx = gradient(x, t), vy = gradient(y, t);
  const ax = gradient(vx, t), ay = gradient(vy, t);
  const jx = gradient(ax, t), jy = gradient(ay, t);
  return { speed: hypot(vx, vy), accel: hypot(ax, ay), jerk: hypot(jx, jy) };
}

export const speedFeatures = (speed) => ({ mean_speed: mean(speed), std_speed: std(speed) });

export function logDimensionlessJerk(t, speed, jerk) {
  const duration = t[t.length - 1] - t[0];
  let dsum = 0;
  for (let i = 1; i < t.length; i++) dsum += t[i] - t[i - 1];
  const dt = dsum / (t.length - 1);

  let jerkIntegral = 0;
  for (let i = 0; i < jerk.length; i++) jerkIntegral += jerk[i] * jerk[i];
  jerkIntegral *= dt;

  const vPeak = maxOf(speed);
  return -Math.log((duration ** 3 / vPeak ** 2) * jerkIntegral);
}

export function sparc(speed, fs, padlevel = 4, fc = 10.0, ampTh = 0.05) {
  // DO NOT simplify - padlevel, fc and ampTh are part of the published
  // definition (Balasubramanian 2015) and every comparable number depends on them
  const nfft = 2 ** (Math.ceil(Math.log2(speed.length)) + padlevel);
  const f = arange(0, fs, fs / nfft);
  const Mf = fftMag(speed, nfft);
  const peak = maxOf(Mf);
  for (let i = 0; i < Mf.length; i++) Mf[i] /= peak;

  let last = -1;
  for (let i = 0; i < f.length; i++) if (f[i] <= fc) last = i;
  let lo = -1, hi = -1;
  for (let i = 0; i <= last; i++) if (Mf[i] >= ampTh) { if (lo < 0) lo = i; hi = i; }
  if (lo < 0 || hi - lo < 1) return NaN;

  const span = f[hi] - f[lo];
  let arc = 0;
  for (let i = lo; i < hi; i++) {
    arc += Math.hypot((f[i + 1] - f[i]) / span, Mf[i + 1] - Mf[i]);
  }
  return -arc;
}

// --- tremor ----------------------------------------------------------

export function tremorResidual(x, y, fs, cutoff = 2.0) {
  const { b, a } = butter(2, cutoff, fs, "high");
  return filtfilt(b, a, hypot(x, y));
  // High-pass the radius so the spiral's slow growth drops out
}

const _welch = (sig, fs) => welch(sig, fs, Math.min(sig.length, Math.trunc(fs * 4)));

export function bandPower(sig, fs, band) {
  const { freqs, psd } = _welch(sig, fs);
  const f = [], p = [];
  for (let i = 0; i < freqs.length; i++) {
    if (freqs[i] >= band[0] && freqs[i] <= band[1]) { f.push(freqs[i]); p.push(psd[i]); }
  }
  if (f.length < 2) return NaN;
  let area = 0;
  for (let i = 0; i < f.length - 1; i++) area += ((p[i] + p[i + 1]) / 2) * (f[i + 1] - f[i]);
  return area;
}

export function dominantFrequency(sig, fs, band = [3.0, 12.0]) {
  const { freqs, psd } = _welch(sig, fs);
  let best = -1, bestP = -Infinity;
  for (let i = 0; i < freqs.length; i++) {
    if (freqs[i] >= band[0] && freqs[i] <= band[1] && psd[i] > bestP) { bestP = psd[i]; best = i; }
  }
  return best < 0 ? NaN : freqs[best];
}

// --- assembly --------------------------------------------------------

export function extractSpiralFeatures(t, x, y, fs = 100.0) {
  const d = spiralFitResidual(x, y);
  const { speed, jerk } = kinematics(t, x, y);
  const residual = tremorResidual(x, y, fs);

  const dev = deviationFeatures(d);
  const spd = speedFeatures(speed);

  return {
    spiral_duration: t[t.length - 1] - t[0],
    spiral_max_deviation: dev.max_deviation,
    spiral_mean_deviation: dev.mean_deviation,
    spiral_std_deviation: dev.std_deviation,
    spiral_major_reversals: majorRadiusReversals(x, y),
    spiral_mean_speed: spd.mean_speed,
    spiral_std_speed: spd.std_speed,
    spiral_ldlj: logDimensionlessJerk(t, speed, jerk),
    spiral_sparc: sparc(speed, fs),
    spiral_tremor_4_6: bandPower(residual, fs, [4.0, 6.0]),
    spiral_tremor_6_12: bandPower(residual, fs, [6.0, 12.0]),
    spiral_tremor_dominant_hz: dominantFrequency(residual, fs),
  };
}

// The front door - takes the trace object the app records
export function featuresFromTrace(trace, fs = 100.0) {
  if (trace.task !== "spiral") throw new Error(`no feature extractor for task ${trace.task}`);
  const t = Float64Array.from(trace.samples, (s) => s.t);
  const x = Float64Array.from(trace.samples, (s) => s.x);
  const y = Float64Array.from(trace.samples, (s) => s.y);
  const [pt, px, py] = preprocessTrace(t, x, y, fs);
  return extractSpiralFeatures(pt, px, py, fs);
}

// Features as a plain array in featureOrder - what the model consumes
export const featureVector = (f) => SPIRAL_FEATURE_ORDER.map((k) => f[k]);
