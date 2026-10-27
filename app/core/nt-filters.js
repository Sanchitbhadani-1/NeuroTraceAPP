// NT-FILTERS.JS HOLDS THE BUTTERWORTH FILTER DESIGN, FILTFILT AND WELCH, MATCHED TO SCIPY.SIGNAL
// THE AWKWARD DETAILS HERE COME FROM SCIPY, LIKE THE ODD PADDING LENGTH, THE STEADY STATE STARTING VALUES AND THE PERIODIC HANN WINDOW
// GETTING ONE WRONG ONLY MOVES THE NUMBERS AT THE EDGES, WHICH IS THE KIND OF BUG THE PARITY TEST CATCHES AND AN EYE DOESN'T

import { solve, fft } from "./nt-signal.js";


// COMPLEX NUMBERS, KEPT AS [REAL, IMAGINARY]

// Multiply two complex numbers
function cMul(a, b) {
  return [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]];
}


// Divide complex number a by b
function cDiv(a, b) {
  const d = b[0] * b[0] + b[1] * b[1];
  return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d];
}


// Find a polynomial's coefficients from its roots, like np.poly, keeping the real parts
function poly(roots) {
  let c = [[1, 0]];
  for (const r of roots) {

    // Multiply the polynomial so far by (x - r)
    const next = [];
    for (let i = 0; i < c.length + 1; i++) {
      next.push([0, 0]);
    }
    for (let i = 0; i < c.length; i++) {
      next[i][0] += c[i][0];
      next[i][1] += c[i][1];
      const m = cMul(c[i], r);
      next[i + 1][0] -= m[0];
      next[i + 1][1] -= m[1];
    }
    c = next;
  }

  // Keep the real part of each coefficient
  const out = [];
  for (const v of c) {
    out.push(v[0]);
  }
  return out;
}


// THE BUTTERWORTH FILTER

// Design a Butterworth filter like scipy.signal.butter(order, cutoff, btype, fs), and give back its { b, a }
export function butter(order, cutoff, fs, btype = "low") {

  // SciPy scales the cutoff so Nyquist is 1, then does the bilinear transform at fs = 2
  // That makes the constant for pre-warping 2 * 2 = 4
  const Wn = (2 * cutoff) / fs;
  const warped = 4 * Math.tan((Math.PI * Wn) / 2);

  // Start with the poles of an analog Butterworth filter with a cutoff of 1, spaced around the left half of the unit circle
  let p = [];
  for (let k = 0; k < order; k++) {
    const th = (Math.PI * (2 * k + order + 1)) / (2 * order);
    p.push([Math.cos(th), Math.sin(th)]);
  }
  let z = [];
  let k = 1;

  // Move the cutoff to the warped frequency
  if (btype === "low") {

    // A low pass filter scales the poles up and has no zeros
    k *= Math.pow(warped, order);
    const scaled = [];
    for (const v of p) {
      scaled.push([v[0] * warped, v[1] * warped]);
    }
    p = scaled;
  } else {

    // A high pass filter flips each pole around, and gets a zero at 0 for each pole
    let pr = [1, 0];
    for (const v of p) {
      pr = cMul(pr, [-v[0], -v[1]]);
    }
    k *= cDiv([1, 0], pr)[0];
    const flipped = [];
    for (const v of p) {
      flipped.push(cDiv([warped, 0], v));
    }
    p = flipped;
    z = [];
    for (let i = 0; i < p.length; i++) {
      z.push([0, 0]);
    }
  }

  // The bilinear transform at fs = 2 uses 2 * fs, which is 4
  const fs2 = 4;
  const degree = p.length - z.length;

  // Fix the gain for the bilinear transform
  let num = [1, 0];
  let den = [1, 0];
  for (const v of z) {
    num = cMul(num, [fs2 - v[0], -v[1]]);
  }
  for (const v of p) {
    den = cMul(den, [fs2 - v[0], -v[1]]);
  }
  k *= cDiv(num, den)[0];

  // Move each zero and pole to the digital filter, and add a zero at -1 for each pole without a zero
  const zz = [];
  for (const v of z) {
    zz.push(cDiv([fs2 + v[0], v[1]], [fs2 - v[0], -v[1]]));
  }
  const pz = [];
  for (const v of p) {
    pz.push(cDiv([fs2 + v[0], v[1]], [fs2 - v[0], -v[1]]));
  }
  for (let i = 0; i < degree; i++) {
    zz.push([-1, 0]);
  }

  // Multiply the zeros and poles out into the filter's coefficients
  const b = [];
  for (const v of poly(zz)) {
    b.push(v * k);
  }
  return { b, a: poly(pz) };
}


// Run a filter over x like scipy.signal.lfilter, in direct form II transposed, starting from the state zi
function lfilter(b, a, x, zi) {
  const n = Math.max(a.length, b.length);

  // Pad both lists of coefficients to the same length, and divide them by a[0]
  const bb = new Array(n).fill(0);
  const aa = new Array(n).fill(0);
  for (let i = 0; i < b.length; i++) {
    bb[i] = b[i] / a[0];
  }
  for (let i = 0; i < a.length; i++) {
    aa[i] = a[i] / a[0];
  }

  // Start from zi when it is given, otherwise from 0
  const z = new Array(n - 1).fill(0);
  if (zi) {
    for (let i = 0; i < zi.length; i++) {
      z[i] = zi[i];
    }
  }

  // Work out each output from the input and the state, then update the state
  const y = new Float64Array(x.length);
  for (let m = 0; m < x.length; m++) {
    y[m] = bb[0] * x[m] + z[0];
    for (let i = 0; i < n - 2; i++) {
      z[i] = bb[i + 1] * x[m] + z[i + 1] - aa[i + 1] * y[m];
    }
    z[n - 2] = bb[n - 1] * x[m] - aa[n - 1] * y[m];
  }
  return y;
}


// Find the starting state that leaves a constant signal unchanged, like scipy.signal.lfilter_zi
function lfilterZi(b, a) {
  const n = Math.max(a.length, b.length);

  // Pad both lists of coefficients to the same length, and divide them by a[0]
  const bb = new Array(n).fill(0);
  const aa = new Array(n).fill(0);
  for (let i = 0; i < b.length; i++) {
    bb[i] = b[i] / a[0];
  }
  for (let i = 0; i < a.length; i++) {
    aa[i] = a[i] / a[0];
  }

  // Make M, the companion matrix of a
  const m = n - 1;
  const M = [];
  for (let i = 0; i < m; i++) {
    M.push(new Array(m).fill(0));
  }
  for (let j = 0; j < m; j++) {
    M[0][j] = -aa[j + 1];
  }
  for (let i = 1; i < m; i++) {
    M[i][i - 1] = 1;
  }

  // The solve below wants I minus M flipped over its diagonal
  const A = [];
  for (let i = 0; i < m; i++) {
    const row = [];
    for (let j = 0; j < m; j++) {
      let identity = 0;
      if (i === j) {
        identity = 1;
      }
      row.push(identity - M[j][i]);
    }
    A.push(row);
  }
  const B = [];
  for (let i = 0; i < m; i++) {
    B.push(bb[i + 1] - aa[i + 1] * bb[0]);
  }
  return solve(A, B);
}


// Filter x forward and then backward so nothing shifts in time, like scipy.signal.filtfilt with its defaults
// The defaults pad each end with odd padding, 3 times the number of taps long
export function filtfilt(b, a, x) {
  const ntaps = Math.max(a.length, b.length);
  const edge = ntaps * 3;
  if (x.length <= edge) {
    throw new Error(`trace too short to filter (${x.length} samples)`);
  }

  // Pad each end with the signal flipped upside down around its end value
  const ext = new Float64Array(x.length + 2 * edge);
  for (let i = 0; i < edge; i++) {
    ext[i] = 2 * x[0] - x[edge - i];
  }
  ext.set(x, edge);
  for (let i = 0; i < edge; i++) {
    ext[edge + x.length + i] = 2 * x[x.length - 1] - x[x.length - 2 - i];
  }

  // Filter forward, starting from the steady state for the first value
  const zi = lfilterZi(b, a);
  const ziForward = [];
  for (const v of zi) {
    ziForward.push(v * ext[0]);
  }
  let y = lfilter(b, a, ext, ziForward);

  // The LAST sample of the forward pass starts the backward pass, so read it before reversing
  // Reading it after starts from the first sample instead, and the whole trace is a little wrong while still looking like a filtered spiral
  const y0 = y[y.length - 1];

  // Filter backward, starting from the steady state for that value
  y.reverse();
  const ziBackward = [];
  for (const v of zi) {
    ziBackward.push(v * y0);
  }
  y = lfilter(b, a, y, ziBackward);
  y.reverse();

  // Cut the padding back off
  return y.slice(edge, edge + x.length);
}


// WELCH

// Add the squared size of each one sided bin of seg to out, with a direct DFT
// nperseg is a few hundred, so this is cheap, and it doesn't need a power of two
function periodogram(seg, out) {
  const n = seg.length;
  const half = Math.floor(n / 2) + 1;
  for (let k = 0; k < half; k++) {
    let re = 0;
    let im = 0;
    for (let i = 0; i < n; i++) {
      const ang = (-2 * Math.PI * k * i) / n;
      re += seg[i] * Math.cos(ang);
      im += seg[i] * Math.sin(ang);
    }
    out[k] += re * re + im * im;
  }
}


// Find the power at each frequency, like scipy.signal.welch(sig, fs, nperseg) with its defaults
// The defaults are a periodic Hann window, 50% overlap, the average taken off each piece, density scaling and the mean of the pieces
export function welch(sig, fs, nperseg) {

  // A piece can't be longer than the signal
  nperseg = Math.min(sig.length, nperseg);

  // Make the periodic Hann window, and add up its squares for the scaling
  const win = new Float64Array(nperseg);
  let winSq = 0;
  for (let i = 0; i < nperseg; i++) {
    win[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / nperseg);
    winSq += win[i] * win[i];
  }

  // Pieces overlap by half, and each one gives half its length plus one bins
  const step = nperseg - Math.floor(nperseg / 2);
  const half = Math.floor(nperseg / 2) + 1;
  const acc = new Float64Array(half);
  const seg = new Float64Array(nperseg);

  let count = 0;
  for (let s = 0; s + nperseg <= sig.length; s += step) {

    // Take the piece's average off it, then apply the window
    let m = 0;
    for (let i = 0; i < nperseg; i++) {
      m += sig[s + i];
    }
    m /= nperseg;
    for (let i = 0; i < nperseg; i++) {
      seg[i] = (sig[s + i] - m) * win[i];
    }

    periodogram(seg, acc);
    count++;
  }

  // Average the pieces and scale them, and double every bin except the first and, for an even length, the last
  const scale = 1 / (fs * winSq);
  const psd = new Float64Array(half);
  const freqs = new Float64Array(half);
  for (let k = 0; k < half; k++) {
    const v = (acc[k] / count) * scale;
    const isEdge = k === 0 || (nperseg % 2 === 0 && k === half - 1);
    if (isEdge) {
      psd[k] = v;
    } else {
      psd[k] = v * 2;
    }
    freqs[k] = (k * fs) / nperseg;
  }
  return { freqs, psd };
}