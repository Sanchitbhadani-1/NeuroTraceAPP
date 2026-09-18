// Numerical primitives for NeuroTrace, matched to numpy/scipy.
// Every function here has a Python counterpart the parity test compares against.
// If you change one, change the other and re-run tools/parity.mjs.

// --- basics ----------------------------------------------------------

export const mean = (v) => v.reduce((s, n) => s + n, 0) / v.length;

// Math.max(...v) blows the call stack somewhere past ~100k elements, and our
// FFT buffers are bigger than that. Never spread an array into Math.max here.
export function maxOf(v) {
  let m = -Infinity;
  for (let i = 0; i < v.length; i++) if (v[i] > m) m = v[i];
  return m;
}

export function median(v) {
  const s = Float64Array.from(v).sort();
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

export function hypot(a, b) {
  const out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) out[i] = Math.hypot(a[i], b[i]);
  return out;
}

// np.arange(start, stop, step) - length is ceil, endpoint excluded
export function arange(start, stop, step) {
  const n = Math.max(0, Math.ceil((stop - start) / step));
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) out[i] = start + i * step;
  return out;
}

// np.interp - linear, clamped outside the range
export function interp(xNew, xp, fp) {
  const out = new Float64Array(xNew.length);
  let j = 0;
  for (let i = 0; i < xNew.length; i++) {
    const v = xNew[i];
    if (v <= xp[0]) { out[i] = fp[0]; continue; }
    if (v >= xp[xp.length - 1]) { out[i] = fp[fp.length - 1]; continue; }
    while (j < xp.length - 2 && xp[j + 1] < v) j++;
    while (j > 0 && xp[j] > v) j--;
    const w = (v - xp[j]) / (xp[j + 1] - xp[j]);
    out[i] = fp[j] + w * (fp[j + 1] - fp[j]);
  }
  return out;
}

// np.unwrap
export function unwrap(p) {
  const out = Float64Array.from(p);
  let corr = 0;
  for (let i = 1; i < out.length; i++) {
    let d = p[i] - p[i - 1];
    if (d > Math.PI) corr -= 2 * Math.PI;
    else if (d < -Math.PI) corr += 2 * Math.PI;
    out[i] = p[i] + corr;
  }
  return out;
}

// np.gradient(f, t), edge_order=1: second-order centred inside, one-sided at
// the ends. Written for uneven t even though ours is even after resampling.
export function gradient(f, t) {
  const n = f.length;
  const out = new Float64Array(n);
  out[0] = (f[1] - f[0]) / (t[1] - t[0]);
  out[n - 1] = (f[n - 1] - f[n - 2]) / (t[n - 1] - t[n - 2]);
  for (let i = 1; i < n - 1; i++) {
    const d1 = t[i] - t[i - 1], d2 = t[i + 1] - t[i];
    out[i] = (-d2 / (d1 * (d1 + d2))) * f[i - 1]
           + ((d2 - d1) / (d1 * d2)) * f[i]
           + (d1 / (d2 * (d1 + d2))) * f[i + 1];
  }
  return out;
}

// --- small dense linear algebra --------------------------------------

// Gaussian elimination with partial pivoting. n is small (<= 4 here).
export function solve(A, b) {
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      const k = M[r][c] / M[c][c];
      for (let j = c; j <= n; j++) M[r][j] -= k * M[c][j];
    }
  }
  return M.map((row, i) => row[n] / row[i]);
}

// Least squares via the normal equations. Fine for the 4 well-scaled columns
// we use; do not reach for this with a near-singular design matrix.
export function lstsq(cols, y) {
  const k = cols.length;
  const AtA = Array.from({ length: k }, () => new Array(k).fill(0));
  const Aty = new Array(k).fill(0);
  for (let i = 0; i < k; i++) {
    for (let j = i; j < k; j++) {
      let s = 0;
      for (let m = 0; m < y.length; m++) s += cols[i][m] * cols[j][m];
      AtA[i][j] = AtA[j][i] = s;
    }
    let s = 0;
    for (let m = 0; m < y.length; m++) s += cols[i][m] * y[m];
    Aty[i] = s;
  }
  return solve(AtA, Aty);
}

// --- FFT -------------------------------------------------------------

// In-place iterative radix-2 Cooley-Tukey. n must be a power of two.
export function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len;
    const wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k];
        const vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
        const vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi;
        re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr; cr = ncr;
      }
    }
  }
}

// Magnitude of the first n/2+1 bins (what rfft gives you)
export function rfftMag(x, nfft) {
  const re = new Float64Array(nfft), im = new Float64Array(nfft);
  re.set(x.subarray ? x.subarray(0, Math.min(x.length, nfft)) : x.slice(0, nfft));
  fft(re, im);
  const out = new Float64Array(nfft / 2 + 1);
  for (let i = 0; i < out.length; i++) out[i] = Math.hypot(re[i], im[i]);
  return out;
}

// Magnitude of every bin (np.abs(np.fft.fft(x, nfft)))
export function fftMag(x, nfft) {
  const re = new Float64Array(nfft), im = new Float64Array(nfft);
  for (let i = 0; i < Math.min(x.length, nfft); i++) re[i] = x[i];
  fft(re, im);
  const out = new Float64Array(nfft);
  for (let i = 0; i < nfft; i++) out[i] = Math.hypot(re[i], im[i]);
  return out;
}
