// NT-FEATURES.JS TURNS A SPIRAL DRAWING INTO THE 12 MEASUREMENTS THE MODEL USES
// EACH FUNCTION MATCHES ONE IN PREPROCESS.PY OR FEATURES.PY, AND THE CLEANUP STEPS RUN IN THE SAME ORDER AS THE PYTHON
// ONLY SPIRALS ARE HANDLED FOR NOW

import { mean, maxOf, median, hypot, arange, interp, unwrap, gradient, lstsq, fftMag } from "./nt-signal.js";
import { butter, filtfilt, welch } from "./nt-filters.js";

export const SPIRAL_FEATURE_ORDER = [
  "spiral_duration",
  "spiral_max_deviation", "spiral_mean_deviation", "spiral_std_deviation",
  "spiral_major_reversals",
  "spiral_mean_speed", "spiral_std_speed",
  "spiral_ldlj", "spiral_sparc",
  "spiral_tremor_4_6", "spiral_tremor_6_12", "spiral_tremor_dominant_hz",
];
// The 12 measurements in the same order as featureOrder in model.json, new ones only go at the end


// Find the standard deviation of a list of numbers
function std(v) {

  // Find the average
  const m = mean(v);

  // Find how far each number is from the average, squared
  const squares = [];
  for (let i = 0; i < v.length; i++) {
    squares.push((v[i] - m) ** 2);
  }

  // Take the square root of the average of those
  return Math.sqrt(mean(squares));
}


// Remove bad points from the drawing
export function clean(t, x, y) {

  // Create empty lists for the kept times and positions, and track the latest time kept
  const kt = [];
  const kx = [];
  const ky = [];
  let runningMax = -Infinity;

  for (let i = 0; i < t.length; i++) {

    // Skip a point if its time or position is missing or infinite
    if (!Number.isFinite(t[i]) || !Number.isFinite(x[i]) || !Number.isFinite(y[i])) {
      continue;
    }

    // Keep a point only if its time is later than every time already kept
    if (kt.length === 0 || t[i] > runningMax) {
      kt.push(t[i]);
      kx.push(x[i]);
      ky.push(y[i]);
      runningMax = Math.max(runningMax, t[i]);
    }
  }

  // Return the kept points as number arrays
  return [Float64Array.from(kt), Float64Array.from(kx), Float64Array.from(ky)];
}


// Cut off the still parts at the start and end of the drawing
export function trimStationary(t, x, y, threshold = 0.05, window = 10) {

  // If the drawing is too short to check, return it as is
  if (t.length <= window + 1) {
    return [t, x, y];
  }

  // Find the pen's speed across every 10 points
  const n = t.length - window;
  const speed = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const distance = Math.hypot(x[i + window] - x[i], y[i + window] - y[i]);
    const time = t[i + window] - t[i];
    speed[i] = distance / time;
  }

  // Find the first and last places where the pen moves faster than 5% of its median speed
  const cut = threshold * median(speed);
  let first = -1;
  let last = -1;
  for (let i = 0; i < n; i++) {
    if (speed[i] > cut) {
      if (first < 0) {
        first = i;
      }
      last = i;
    }
  }

  // If the pen never moves that fast, return the drawing as is
  if (first < 0) {
    return [t, x, y];
  }

  // Keep everything between those two places, including pauses in the middle
  const lo = first;
  const hi = Math.min(t.length - 1, last + window);
  return [t.slice(lo, hi + 1), x.slice(lo, hi + 1), y.slice(lo, hi + 1)];
}


// Put the drawing on an even timeline, one point every 1/100 of a second
export function resampleUniform(t, x, y, fs = 100.0) {

  // Stop with an error if any time is not later than the one before it
  for (let i = 1; i < t.length; i++) {
    if (t[i] <= t[i - 1]) {
      throw new Error("timestamps must be strictly increasing");
    }
  }

  // Make the even timeline and estimate the position at each new time from the points around it
  const grid = arange(t[0], t[t.length - 1], 1.0 / fs);
  return [grid, interp(grid, t, x), interp(grid, t, y)];
}


// Center the drawing and scale it to a standard size
export function normalize(x, y) {

  // Move the center of the drawing to 0, 0
  const mx = mean(x);
  const my = mean(y);

  const cx = new Float64Array(x.length);
  for (let i = 0; i < x.length; i++) {
    cx[i] = x[i] - mx;
  }

  const cy = new Float64Array(y.length);
  for (let i = 0; i < y.length; i++) {
    cy[i] = y[i] - my;
  }

  // Find the typical distance of the points from the center
  let s = 0;
  for (let i = 0; i < cx.length; i++) {
    s += cx[i] * cx[i] + cy[i] * cy[i];
  }
  const scale = Math.sqrt(s / cx.length);

  // Divide every point by that distance
  const nx = new Float64Array(cx.length);
  for (let i = 0; i < cx.length; i++) {
    nx[i] = cx[i] / scale;
  }

  const ny = new Float64Array(cy.length);
  for (let i = 0; i < cy.length; i++) {
    ny[i] = cy[i] / scale;
  }

  return [nx, ny];
}


// Smooth the line by removing anything faster than 15 times a second
export function lowPass(t, x, y, fs = 100.0, cutoff = 15.0, order = 4) {

  // Build a Butterworth low pass filter
  const filter = butter(order, cutoff, fs, "low");
  const b = filter.b;
  const a = filter.a;

  // Stop with an error if the drawing is too short to filter
  if (x.length <= 3 * Math.max(a.length, b.length)) {
    throw new Error(`trace too short to filter (${x.length} samples)`);
  }

  // Run the filter forward and backward over x and y
  return [t, filtfilt(b, a, x), filtfilt(b, a, y)];
}


// Run every cleanup step in the same order as the Python
export function preprocessTrace(t, x, y, fs = 100.0, cutoff = 15.0, trim = true) {

  // Remove bad points, then cut off the still parts at the ends
  [t, x, y] = clean(t, x, y);
  if (trim) {
    [t, x, y] = trimStationary(t, x, y);
  }

  // Put it on an even timeline, center and scale it, then smooth it
  [t, x, y] = resampleUniform(t, x, y, fs);
  [x, y] = normalize(x, y);
  return lowPass(t, x, y, fs, cutoff);
}


// Find how far each point is from the best fitting spiral
export function spiralFitResidual(x, y, minTurns = 1.0) {

  // Find each point's angle, counting up through every turn, and its distance from the center
  const angles = new Float64Array(x.length);
  for (let i = 0; i < x.length; i++) {
    angles[i] = Math.atan2(y[i], x[i]);
  }
  const theta = unwrap(angles);
  const r = hypot(x, y);

  // Stop with an error if the drawing covers less than one full turn
  const span = Math.abs(theta[theta.length - 1] - theta[0]) / (2 * Math.PI);
  if (span < minTurns) {
    throw new Error(`trace covers only ${span.toFixed(2)} turns, too little to fit a spiral`);
  }

  // Make the four columns for the fit, a column of ones, the angle, and the cos and sin of the angle
  const ones = new Float64Array(theta.length).fill(1);
  const cos = new Float64Array(theta.length);
  const sin = new Float64Array(theta.length);
  for (let i = 0; i < theta.length; i++) {
    cos[i] = Math.cos(theta[i]);
    sin[i] = Math.sin(theta[i]);
  }

  // Fit a spiral to the points with least squares, plus two terms for a center that is a little off
  const p = lstsq([ones, theta, cos, sin], r);

  // Return the gap between each point's distance and the fitted spiral
  const gaps = new Float64Array(r.length);
  for (let i = 0; i < r.length; i++) {
    const ideal = p[0] + p[1] * theta[i] + p[2] * cos[i] + p[3] * sin[i];
    gaps[i] = r[i] - ideal;
  }
  return gaps;
}


// Count how many times the pen turns back toward or away from the center by more than a small amount
export function majorRadiusReversals(x, y, minRetrace = 0.10) {

  // Find each point's distance from the center, and start with no direction
  const r = hypot(x, y);
  let count = 0;
  let direction = 0;
  let extreme = r[0];

  for (let i = 0; i < r.length; i++) {
    const v = r[i];

    if (direction === 0) {

      // No direction yet, wait for the distance to move up or down by more than 0.10
      if (v > extreme + minRetrace) {
        direction = 1;
        extreme = v;
      } else if (v < extreme - minRetrace) {
        direction = -1;
        extreme = v;
      }

    } else if (direction === 1) {

      // Moving outward, track the farthest distance and count a reversal when it drops back by more than 0.10
      if (v > extreme) {
        extreme = v;
      } else if (v < extreme - minRetrace) {
        count += 1;
        direction = -1;
        extreme = v;
      }

    } else {

      // Moving inward, track the closest distance and count a reversal when it grows back by more than 0.10
      if (v < extreme) {
        extreme = v;
      } else if (v > extreme + minRetrace) {
        count += 1;
        direction = 1;
        extreme = v;
      }
    }
  }

  // Return the number of reversals
  return count;
}


// Turn the gaps from the fitted spiral into three measurements
export function deviationFeatures(d) {

  // Make every gap positive
  const abs = new Float64Array(d.length);
  for (let i = 0; i < d.length; i++) {
    abs[i] = Math.abs(d[i]);
  }

  // Return the biggest gap, the average gap, and how spread out the gaps are
  return {
    max_deviation: maxOf(abs),
    mean_deviation: mean(abs),
    std_deviation: std(d),
  };
}


// Find the speed, acceleration and jerk of the pen at every point
export function kinematics(t, x, y) {

  // Velocity is the change in position, acceleration is the change in velocity, and jerk is the change in acceleration
  const vx = gradient(x, t);
  const vy = gradient(y, t);
  const ax = gradient(vx, t);
  const ay = gradient(vy, t);
  const jx = gradient(ax, t);
  const jy = gradient(ay, t);

  // Combine the x and y parts of each into one number
  return {
    speed: hypot(vx, vy),
    accel: hypot(ax, ay),
    jerk: hypot(jx, jy),
  };
}


// Find the average speed and how spread out the speed is
export function speedFeatures(speed) {
  return {
    mean_speed: mean(speed),
    std_speed: std(speed),
  };
}


// Measure how smooth the movement is with log dimensionless jerk, where a higher number is smoother
export function logDimensionlessJerk(t, speed, jerk) {

  // Find how long the drawing took and the average time between points
  const duration = t[t.length - 1] - t[0];
  let dsum = 0;
  for (let i = 1; i < t.length; i++) {
    dsum += t[i] - t[i - 1];
  }
  const dt = dsum / (t.length - 1);

  // Add up the jerk squared over the whole drawing
  let jerkIntegral = 0;
  for (let i = 0; i < jerk.length; i++) {
    jerkIntegral += jerk[i] * jerk[i];
  }
  jerkIntegral *= dt;

  // Scale it by the duration and the top speed, then take the negative log
  const vPeak = maxOf(speed);
  return -Math.log((duration ** 3 / vPeak ** 2) * jerkIntegral);
}


// Measure how smooth the movement is with SPARC, where a higher number is smoother
export function sparc(speed, fs, padlevel = 4, fc = 10.0, ampTh = 0.05) {

  // padlevel, fc and ampTh come from the published definition in Balasubramanian 2015, and should not be changed
  // Find the frequencies in the speed with an FFT, padded to a longer length
  const nfft = 2 ** (Math.ceil(Math.log2(speed.length)) + padlevel);
  const f = arange(0, fs, fs / nfft);
  const Mf = fftMag(speed, nfft);

  // Divide every frequency strength by the biggest one
  const peak = maxOf(Mf);
  for (let i = 0; i < Mf.length; i++) {
    Mf[i] /= peak;
  }

  // Find the last frequency at or below 10 times a second
  let last = -1;
  for (let i = 0; i < f.length; i++) {
    if (f[i] <= fc) {
      last = i;
    }
  }

  // Find the first and last frequencies up to there with a strength of at least 0.05
  let lo = -1;
  let hi = -1;
  for (let i = 0; i <= last; i++) {
    if (Mf[i] >= ampTh) {
      if (lo < 0) {
        lo = i;
      }
      hi = i;
    }
  }

  // Return NaN if there aren't enough frequencies to measure
  if (lo < 0 || hi - lo < 1) {
    return NaN;
  }

  // Measure the length of the frequency curve between those two points
  const span = f[hi] - f[lo];
  let arc = 0;
  for (let i = lo; i < hi; i++) {
    arc += Math.hypot((f[i + 1] - f[i]) / span, Mf[i + 1] - Mf[i]);
  }

  // Return the negative of that length
  return -arc;
}


// Find the fast shaking in the drawing
export function tremorResidual(x, y, fs, cutoff = 2.0) {

  // Build a high pass filter that removes anything slower than 2 times a second
  const filter = butter(2, cutoff, fs, "high");

  // Run it forward and backward over each point's distance from the center
  const r = hypot(x, y);
  return filtfilt(filter.b, filter.a, r);
}


// Find how strong each frequency is in a signal with Welch's method, using 4 second pieces
function _welch(sig, fs) {
  const pieceLength = Math.min(sig.length, Math.trunc(fs * 4));
  return welch(sig, fs, pieceLength);
}


// Find how much shaking falls inside a band of frequencies, like 4 to 6 times a second
export function bandPower(sig, fs, band) {

  // Find how strong each frequency is
  const spectrum = _welch(sig, fs);
  const freqs = spectrum.freqs;
  const psd = spectrum.psd;

  // Keep only the frequencies inside the band
  const f = [];
  const p = [];
  for (let i = 0; i < freqs.length; i++) {
    if (freqs[i] >= band[0] && freqs[i] <= band[1]) {
      f.push(freqs[i]);
      p.push(psd[i]);
    }
  }

  // Return NaN if fewer than two frequencies are inside the band
  if (f.length < 2) {
    return NaN;
  }

  // Add up the area under the curve inside the band with trapezoids
  let area = 0;
  for (let i = 0; i < f.length - 1; i++) {
    area += ((p[i] + p[i + 1]) / 2) * (f[i + 1] - f[i]);
  }
  return area;
}


// Find the frequency with the strongest shaking between 3 and 12 times a second
export function dominantFrequency(sig, fs, band = [3.0, 12.0]) {

  // Find how strong each frequency is
  const spectrum = _welch(sig, fs);
  const freqs = spectrum.freqs;
  const psd = spectrum.psd;

  // Go through the frequencies inside the band and keep the strongest one
  let best = -1;
  let bestP = -Infinity;
  for (let i = 0; i < freqs.length; i++) {
    if (freqs[i] >= band[0] && freqs[i] <= band[1]) {
      if (psd[i] > bestP) {
        bestP = psd[i];
        best = i;
      }
    }
  }

  // Return that frequency, or NaN if none were inside the band
  if (best < 0) {
    return NaN;
  }
  return freqs[best];
}


// Measure all 12 things about a cleaned up spiral
export function extractSpiralFeatures(t, x, y, fs = 100.0) {

  // Find the gaps from the fitted spiral, the pen's speed and jerk, and the fast shaking
  const d = spiralFitResidual(x, y);
  const motion = kinematics(t, x, y);
  const speed = motion.speed;
  const jerk = motion.jerk;
  const residual = tremorResidual(x, y, fs);

  // Turn those into the deviation and speed measurements
  const dev = deviationFeatures(d);
  const spd = speedFeatures(speed);

  // Return all 12 measurements by name
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


// The function the app calls with a recorded drawing
export function featuresFromTrace(trace, fs = 100.0) {

  // Stop with an error if the drawing isn't a spiral
  if (trace.task !== "spiral") {
    throw new Error(`no feature extractor for task ${trace.task}`);
  }

  // Pull the times and positions out of the recorded points
  const count = trace.samples.length;
  const t = new Float64Array(count);
  const x = new Float64Array(count);
  const y = new Float64Array(count);
  for (let i = 0; i < count; i++) {
    t[i] = trace.samples[i].t;
    x[i] = trace.samples[i].x;
    y[i] = trace.samples[i].y;
  }

  // Clean up the drawing, then measure it
  const cleaned = preprocessTrace(t, x, y, fs);
  return extractSpiralFeatures(cleaned[0], cleaned[1], cleaned[2], fs);
}


// Put the measurements in a plain list, in the order the model expects
export function featureVector(f) {
  const vector = [];
  for (const name of SPIRAL_FEATURE_ORDER) {
    vector.push(f[name]);
  }
  return vector;
}