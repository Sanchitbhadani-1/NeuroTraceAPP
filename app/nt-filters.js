// Butterworth design, filtfilt and Welch, matched to scipy.signal.
// The awkward details here are scipy's, not ours: the odd padding length,
// the steady-state initial conditions, the periodic Hann window. Get one
// wrong and the numbers drift only at the edges, which is exactly the kind
// of bug a parity test catches and an eyeball does not.

import { solve, fft } from "./nt-signal.js";

// --- complex helpers -------------------------------------------------
const cMul = (a, b) => [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]];
const cDiv = (a, b) => {
  const d = b[0] * b[0] + b[1] * b[1];
  return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d];
};

// np.poly - polynomial coefficients from roots
function poly(roots) {
  let c = [[1, 0]];
  for (const r of roots) {
    const next = new Array(c.length + 1).fill(null).map(() => [0, 0]);
    for (let i = 0; i < c.length; i++) {
      next[i][0] += c[i][0]; next[i][1] += c[i][1];
      const m = cMul(c[i], r);
      next[i + 1][0] -= m[0]; next[i + 1][1] -= m[1];
    }
    c = next;
  }
  return c.map((v) => v[0]);
}

// scipy.signal.butter(order, cutoff, btype, fs) -> {b, a}
export function butter(order, cutoff, fs, btype = "low") {
  const Wn = (2 * cutoff) / fs;
  const warped = 4 * Math.tan((Math.PI * Wn) / 2);
  // scipy normalizes to Nyquist = 1 and then bilinear-transforms at fs = 2,
  // so the pre-warp constant is 2 * 2 = 4

  let p = [];
  for (let k = 0; k < order; k++) {
    const th = (Math.PI * (2 * k + order + 1)) / (2 * order);
    p.push([Math.cos(th), Math.sin(th)]);
  }
  let z = [];
  let k = 1;

  if (btype === "low") {
    k *= Math.pow(warped, order);
    p = p.map((v) => [v[0] * warped, v[1] * warped]);
  } else {
    let pr = [1, 0];
    for (const v of p) pr = cMul(pr, [-v[0], -v[1]]);
    k *= cDiv([1, 0], pr)[0];
    p = p.map((v) => cDiv([warped, 0], v));
    z = p.map(() => [0, 0]);
  }

  const fs2 = 4;
  const degree = p.length - z.length;
  let num = [1, 0], den = [1, 0];
  for (const v of z) num = cMul(num, [fs2 - v[0], -v[1]]);
  for (const v of p) den = cMul(den, [fs2 - v[0], -v[1]]);
  k *= cDiv(num, den)[0];

  const zz = z.map((v) => cDiv([fs2 + v[0], v[1]], [fs2 - v[0], -v[1]]));
  const pz = p.map((v) => cDiv([fs2 + v[0], v[1]], [fs2 - v[0], -v[1]]));
  for (let i = 0; i < degree; i++) zz.push([-1, 0]);

  return { b: poly(zz).map((v) => v * k), a: poly(pz) };
}

// scipy.signal.lfilter, direct form II transposed
function lfilter(b, a, x, zi) {
  const n = Math.max(a.length, b.length);
  const bb = new Array(n).fill(0), aa = new Array(n).fill(0);
  b.forEach((v, i) => (bb[i] = v / a[0]));
  a.forEach((v, i) => (aa[i] = v / a[0]));

  const z = new Array(n - 1).fill(0);
  if (zi) zi.forEach((v, i) => (z[i] = v));

  const y = new Float64Array(x.length);
  for (let m = 0; m < x.length; m++) {
    y[m] = bb[0] * x[m] + z[0];
    for (let i = 0; i < n - 2; i++) z[i] = bb[i + 1] * x[m] + z[i + 1] - aa[i + 1] * y[m];
    z[n - 2] = bb[n - 1] * x[m] - aa[n - 1] * y[m];
  }
  return y;
}

// scipy.signal.lfilter_zi - the state that leaves a constant signal unchanged
function lfilterZi(b, a) {
  const n = Math.max(a.length, b.length);
  const bb = new Array(n).fill(0), aa = new Array(n).fill(0);
  b.forEach((v, i) => (bb[i] = v / a[0]));
  a.forEach((v, i) => (aa[i] = v / a[0]));

  const m = n - 1;
  const M = Array.from({ length: m }, () => new Array(m).fill(0));
  for (let j = 0; j < m; j++) M[0][j] = -aa[j + 1];
  for (let i = 1; i < m; i++) M[i][i - 1] = 1;
  // companion(a); the solve below wants I - companion(a).T

  const A = Array.from({ length: m }, (_, i) =>
    Array.from({ length: m }, (_, j) => (i === j ? 1 : 0) - M[j][i]));
  const B = Array.from({ length: m }, (_, i) => bb[i + 1] - aa[i + 1] * bb[0]);
  return solve(A, B);
}

// scipy.signal.filtfilt with its defaults: padtype "odd", padlen 3 * ntaps
export function filtfilt(b, a, x) {
  const ntaps = Math.max(a.length, b.length);
  const edge = ntaps * 3;
  if (x.length <= edge) throw new Error(`trace too short to filter (${x.length} samples)`);

  const ext = new Float64Array(x.length + 2 * edge);
  for (let i = 0; i < edge; i++) ext[i] = 2 * x[0] - x[edge - i];
  ext.set(x, edge);
  for (let i = 0; i < edge; i++) ext[edge + x.length + i] = 2 * x[x.length - 1] - x[x.length - 2 - i];

  const zi = lfilterZi(b, a);
  let y = lfilter(b, a, ext, zi.map((v) => v * ext[0]));

  const y0 = y[y.length - 1];
  // The LAST sample of the forward pass seeds the backward pass. Read it
  // before reversing or you seed with the first sample and the whole trace
  // is subtly wrong - it still looks like a filtered spiral.

  y.reverse();
  y = lfilter(b, a, y, zi.map((v) => v * y0));
  y.reverse();
  return y.slice(edge, edge + x.length);
}

// --- Welch -----------------------------------------------------------

// Direct DFT magnitude-squared for the one-sided bins. nperseg is a few
// hundred, so this is cheap, and it avoids needing a power of two.
function periodogram(seg, out) {
  const n = seg.length;
  const half = (n >> 1) + 1;
  for (let k = 0; k < half; k++) {
    let re = 0, im = 0;
    for (let i = 0; i < n; i++) {
      const ang = (-2 * Math.PI * k * i) / n;
      re += seg[i] * Math.cos(ang);
      im += seg[i] * Math.sin(ang);
    }
    out[k] += re * re + im * im;
  }
}

// scipy.signal.welch(sig, fs, nperseg) with its defaults:
// Hann (periodic), 50% overlap, detrend "constant", density scaling, mean average
export function welch(sig, fs, nperseg) {
  nperseg = Math.min(sig.length, nperseg);
  const win = new Float64Array(nperseg);
  let winSq = 0;
  for (let i = 0; i < nperseg; i++) {
    win[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / nperseg);
    winSq += win[i] * win[i];
  }

  const step = nperseg - (nperseg >> 1);
  const half = (nperseg >> 1) + 1;
  const acc = new Float64Array(half);
  const seg = new Float64Array(nperseg);

  let count = 0;
  for (let s = 0; s + nperseg <= sig.length; s += step) {
    let m = 0;
    for (let i = 0; i < nperseg; i++) m += sig[s + i];
    m /= nperseg;
    for (let i = 0; i < nperseg; i++) seg[i] = (sig[s + i] - m) * win[i];
    periodogram(seg, acc);
    count++;
  }

  const scale = 1 / (fs * winSq);
  const psd = new Float64Array(half);
  const freqs = new Float64Array(half);
  for (let k = 0; k < half; k++) {
    let v = (acc[k] / count) * scale;
    const isEdge = k === 0 || (nperseg % 2 === 0 && k === half - 1);
    psd[k] = isEdge ? v : v * 2;
    freqs[k] = (k * fs) / nperseg;
  }
  return { freqs, psd };
}
