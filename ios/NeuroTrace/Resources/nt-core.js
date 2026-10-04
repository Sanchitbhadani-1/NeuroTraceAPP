var NT = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // js/core.js
  var core_exports = {};
  __export(core_exports, {
    call: () => call,
    callKeep: () => callKeep
  });

  // ../app/nt-features.js
  var nt_features_exports = {};
  __export(nt_features_exports, {
    SPIRAL_FEATURE_ORDER: () => SPIRAL_FEATURE_ORDER,
    bandPower: () => bandPower,
    clean: () => clean,
    deviationFeatures: () => deviationFeatures,
    dominantFrequency: () => dominantFrequency,
    extractSpiralFeatures: () => extractSpiralFeatures,
    featureVector: () => featureVector,
    featuresFromTrace: () => featuresFromTrace,
    kinematics: () => kinematics,
    logDimensionlessJerk: () => logDimensionlessJerk,
    lowPass: () => lowPass,
    majorRadiusReversals: () => majorRadiusReversals,
    normalize: () => normalize,
    preprocessTrace: () => preprocessTrace,
    resampleUniform: () => resampleUniform,
    sparc: () => sparc,
    speedFeatures: () => speedFeatures,
    spiralFitResidual: () => spiralFitResidual,
    tremorResidual: () => tremorResidual,
    trimStationary: () => trimStationary
  });

  // ../app/nt-signal.js
  var mean = (v) => v.reduce((s, n) => s + n, 0) / v.length;
  function maxOf(v) {
    let m = -Infinity;
    for (let i = 0; i < v.length; i++) if (v[i] > m) m = v[i];
    return m;
  }
  function median(v) {
    const s = Float64Array.from(v).sort();
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  }
  function hypot(a, b) {
    const out = new Float64Array(a.length);
    for (let i = 0; i < a.length; i++) out[i] = Math.hypot(a[i], b[i]);
    return out;
  }
  function arange(start, stop, step) {
    const n = Math.max(0, Math.ceil((stop - start) / step));
    const out = new Float64Array(n);
    for (let i = 0; i < n; i++) out[i] = start + i * step;
    return out;
  }
  function interp(xNew, xp, fp) {
    const out = new Float64Array(xNew.length);
    let j = 0;
    for (let i = 0; i < xNew.length; i++) {
      const v = xNew[i];
      if (v <= xp[0]) {
        out[i] = fp[0];
        continue;
      }
      if (v >= xp[xp.length - 1]) {
        out[i] = fp[fp.length - 1];
        continue;
      }
      while (j < xp.length - 2 && xp[j + 1] < v) j++;
      while (j > 0 && xp[j] > v) j--;
      const w = (v - xp[j]) / (xp[j + 1] - xp[j]);
      out[i] = fp[j] + w * (fp[j + 1] - fp[j]);
    }
    return out;
  }
  function unwrap(p) {
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
  function gradient(f, t) {
    const n = f.length;
    const out = new Float64Array(n);
    out[0] = (f[1] - f[0]) / (t[1] - t[0]);
    out[n - 1] = (f[n - 1] - f[n - 2]) / (t[n - 1] - t[n - 2]);
    for (let i = 1; i < n - 1; i++) {
      const d1 = t[i] - t[i - 1], d2 = t[i + 1] - t[i];
      out[i] = -d2 / (d1 * (d1 + d2)) * f[i - 1] + (d2 - d1) / (d1 * d2) * f[i] + d1 / (d2 * (d1 + d2)) * f[i + 1];
    }
    return out;
  }
  function solve(A, b) {
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
  function lstsq(cols, y) {
    const k = cols.length;
    const AtA = Array.from({ length: k }, () => new Array(k).fill(0));
    const Aty = new Array(k).fill(0);
    for (let i = 0; i < k; i++) {
      for (let j = i; j < k; j++) {
        let s2 = 0;
        for (let m = 0; m < y.length; m++) s2 += cols[i][m] * cols[j][m];
        AtA[i][j] = AtA[j][i] = s2;
      }
      let s = 0;
      for (let m = 0; m < y.length; m++) s += cols[i][m] * y[m];
      Aty[i] = s;
    }
    return solve(AtA, Aty);
  }
  function fft(re, im) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
      let bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        [re[i], re[j]] = [re[j], re[i]];
        [im[i], im[j]] = [im[j], im[i]];
      }
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
          re[i + k] = ur + vr;
          im[i + k] = ui + vi;
          re[i + k + len / 2] = ur - vr;
          im[i + k + len / 2] = ui - vi;
          const ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }
  function fftMag(x, nfft) {
    const re = new Float64Array(nfft), im = new Float64Array(nfft);
    for (let i = 0; i < Math.min(x.length, nfft); i++) re[i] = x[i];
    fft(re, im);
    const out = new Float64Array(nfft);
    for (let i = 0; i < nfft; i++) out[i] = Math.hypot(re[i], im[i]);
    return out;
  }

  // ../app/nt-filters.js
  var cMul = (a, b) => [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]];
  var cDiv = (a, b) => {
    const d = b[0] * b[0] + b[1] * b[1];
    return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d];
  };
  function poly(roots) {
    let c = [[1, 0]];
    for (const r of roots) {
      const next = new Array(c.length + 1).fill(null).map(() => [0, 0]);
      for (let i = 0; i < c.length; i++) {
        next[i][0] += c[i][0];
        next[i][1] += c[i][1];
        const m = cMul(c[i], r);
        next[i + 1][0] -= m[0];
        next[i + 1][1] -= m[1];
      }
      c = next;
    }
    return c.map((v) => v[0]);
  }
  function butter(order, cutoff, fs, btype = "low") {
    const Wn = 2 * cutoff / fs;
    const warped = 4 * Math.tan(Math.PI * Wn / 2);
    let p = [];
    for (let k2 = 0; k2 < order; k2++) {
      const th = Math.PI * (2 * k2 + order + 1) / (2 * order);
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
  function lfilter(b, a, x, zi) {
    const n = Math.max(a.length, b.length);
    const bb = new Array(n).fill(0), aa = new Array(n).fill(0);
    b.forEach((v, i) => bb[i] = v / a[0]);
    a.forEach((v, i) => aa[i] = v / a[0]);
    const z = new Array(n - 1).fill(0);
    if (zi) zi.forEach((v, i) => z[i] = v);
    const y = new Float64Array(x.length);
    for (let m = 0; m < x.length; m++) {
      y[m] = bb[0] * x[m] + z[0];
      for (let i = 0; i < n - 2; i++) z[i] = bb[i + 1] * x[m] + z[i + 1] - aa[i + 1] * y[m];
      z[n - 2] = bb[n - 1] * x[m] - aa[n - 1] * y[m];
    }
    return y;
  }
  function lfilterZi(b, a) {
    const n = Math.max(a.length, b.length);
    const bb = new Array(n).fill(0), aa = new Array(n).fill(0);
    b.forEach((v, i) => bb[i] = v / a[0]);
    a.forEach((v, i) => aa[i] = v / a[0]);
    const m = n - 1;
    const M = Array.from({ length: m }, () => new Array(m).fill(0));
    for (let j = 0; j < m; j++) M[0][j] = -aa[j + 1];
    for (let i = 1; i < m; i++) M[i][i - 1] = 1;
    const A = Array.from({ length: m }, (_, i) => Array.from({ length: m }, (_2, j) => (i === j ? 1 : 0) - M[j][i]));
    const B = Array.from({ length: m }, (_, i) => bb[i + 1] - aa[i + 1] * bb[0]);
    return solve(A, B);
  }
  function filtfilt(b, a, x) {
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
    y.reverse();
    y = lfilter(b, a, y, zi.map((v) => v * y0));
    y.reverse();
    return y.slice(edge, edge + x.length);
  }
  function periodogram(seg, out) {
    const n = seg.length;
    const half = (n >> 1) + 1;
    for (let k = 0; k < half; k++) {
      let re = 0, im = 0;
      for (let i = 0; i < n; i++) {
        const ang = -2 * Math.PI * k * i / n;
        re += seg[i] * Math.cos(ang);
        im += seg[i] * Math.sin(ang);
      }
      out[k] += re * re + im * im;
    }
  }
  function welch(sig, fs, nperseg) {
    nperseg = Math.min(sig.length, nperseg);
    const win = new Float64Array(nperseg);
    let winSq = 0;
    for (let i = 0; i < nperseg; i++) {
      win[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / nperseg);
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
      let v = acc[k] / count * scale;
      const isEdge = k === 0 || nperseg % 2 === 0 && k === half - 1;
      psd[k] = isEdge ? v : v * 2;
      freqs[k] = k * fs / nperseg;
    }
    return { freqs, psd };
  }

  // ../app/nt-features.js
  var SPIRAL_FEATURE_ORDER = [
    "spiral_duration",
    "spiral_max_deviation",
    "spiral_mean_deviation",
    "spiral_std_deviation",
    "spiral_major_reversals",
    "spiral_mean_speed",
    "spiral_std_speed",
    "spiral_ldlj",
    "spiral_sparc",
    "spiral_tremor_4_6",
    "spiral_tremor_6_12",
    "spiral_tremor_dominant_hz"
  ];
  var std = (v) => {
    const m = mean(v);
    return Math.sqrt(mean(Array.from(v, (n) => (n - m) ** 2)));
  };
  function clean(t, x, y) {
    const kt = [], kx = [], ky = [];
    let runningMax = -Infinity;
    for (let i = 0; i < t.length; i++) {
      if (!Number.isFinite(t[i]) || !Number.isFinite(x[i]) || !Number.isFinite(y[i])) continue;
      if (kt.length === 0 || t[i] > runningMax) {
        kt.push(t[i]);
        kx.push(x[i]);
        ky.push(y[i]);
        runningMax = Math.max(runningMax, t[i]);
      }
    }
    return [Float64Array.from(kt), Float64Array.from(kx), Float64Array.from(ky)];
  }
  function trimStationary(t, x, y, threshold = 0.05, window = 10) {
    if (t.length <= window + 1) return [t, x, y];
    const n = t.length - window;
    const speed = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      speed[i] = Math.hypot(x[i + window] - x[i], y[i + window] - y[i]) / (t[i + window] - t[i]);
    }
    const cut = threshold * median(speed);
    let first = -1, last = -1;
    for (let i = 0; i < n; i++) if (speed[i] > cut) {
      if (first < 0) first = i;
      last = i;
    }
    if (first < 0) return [t, x, y];
    const lo = first, hi = Math.min(t.length - 1, last + window);
    return [t.slice(lo, hi + 1), x.slice(lo, hi + 1), y.slice(lo, hi + 1)];
  }
  function resampleUniform(t, x, y, fs = 100) {
    for (let i = 1; i < t.length; i++) {
      if (t[i] <= t[i - 1]) throw new Error("timestamps must be strictly increasing");
    }
    const grid = arange(t[0], t[t.length - 1], 1 / fs);
    return [grid, interp(grid, t, x), interp(grid, t, y)];
  }
  function normalize(x, y) {
    const mx = mean(x), my = mean(y);
    const cx = Float64Array.from(x, (v) => v - mx);
    const cy = Float64Array.from(y, (v) => v - my);
    let s = 0;
    for (let i = 0; i < cx.length; i++) s += cx[i] * cx[i] + cy[i] * cy[i];
    const scale = Math.sqrt(s / cx.length);
    return [Float64Array.from(cx, (v) => v / scale), Float64Array.from(cy, (v) => v / scale)];
  }
  function lowPass(t, x, y, fs = 100, cutoff = 15, order = 4) {
    const { b, a } = butter(order, cutoff, fs, "low");
    if (x.length <= 3 * Math.max(a.length, b.length)) {
      throw new Error(`trace too short to filter (${x.length} samples)`);
    }
    return [t, filtfilt(b, a, x), filtfilt(b, a, y)];
  }
  function preprocessTrace(t, x, y, fs = 100, cutoff = 15, trim = true) {
    [t, x, y] = clean(t, x, y);
    if (trim) [t, x, y] = trimStationary(t, x, y);
    [t, x, y] = resampleUniform(t, x, y, fs);
    [x, y] = normalize(x, y);
    return lowPass(t, x, y, fs, cutoff);
  }
  function spiralFitResidual(x, y, minTurns = 1) {
    const theta = unwrap(Float64Array.from(x, (v, i) => Math.atan2(y[i], v)));
    const r = hypot(x, y);
    const span = Math.abs(theta[theta.length - 1] - theta[0]) / (2 * Math.PI);
    if (span < minTurns) throw new Error(`trace covers only ${span.toFixed(2)} turns, too little to fit a spiral`);
    const ones = new Float64Array(theta.length).fill(1);
    const cos = Float64Array.from(theta, Math.cos);
    const sin = Float64Array.from(theta, Math.sin);
    const p = lstsq([ones, theta, cos, sin], r);
    return Float64Array.from(r, (v, i) => v - (p[0] + p[1] * theta[i] + p[2] * cos[i] + p[3] * sin[i]));
  }
  function majorRadiusReversals(x, y, minRetrace = 0.1) {
    const r = hypot(x, y);
    let count = 0, direction = 0, extreme = r[0];
    for (let i = 0; i < r.length; i++) {
      const v = r[i];
      if (direction === 0) {
        if (v > extreme + minRetrace) {
          direction = 1;
          extreme = v;
        } else if (v < extreme - minRetrace) {
          direction = -1;
          extreme = v;
        }
      } else if (direction === 1) {
        if (v > extreme) extreme = v;
        else if (v < extreme - minRetrace) {
          count++;
          direction = -1;
          extreme = v;
        }
      } else {
        if (v < extreme) extreme = v;
        else if (v > extreme + minRetrace) {
          count++;
          direction = 1;
          extreme = v;
        }
      }
    }
    return count;
  }
  function deviationFeatures(d) {
    const abs = Float64Array.from(d, Math.abs);
    return {
      max_deviation: maxOf(abs),
      mean_deviation: mean(abs),
      std_deviation: std(d)
    };
  }
  function kinematics(t, x, y) {
    const vx = gradient(x, t), vy = gradient(y, t);
    const ax = gradient(vx, t), ay = gradient(vy, t);
    const jx = gradient(ax, t), jy = gradient(ay, t);
    return { speed: hypot(vx, vy), accel: hypot(ax, ay), jerk: hypot(jx, jy) };
  }
  var speedFeatures = (speed) => ({ mean_speed: mean(speed), std_speed: std(speed) });
  function logDimensionlessJerk(t, speed, jerk) {
    const duration = t[t.length - 1] - t[0];
    let dsum = 0;
    for (let i = 1; i < t.length; i++) dsum += t[i] - t[i - 1];
    const dt = dsum / (t.length - 1);
    let jerkIntegral = 0;
    for (let i = 0; i < jerk.length; i++) jerkIntegral += jerk[i] * jerk[i];
    jerkIntegral *= dt;
    const vPeak = maxOf(speed);
    return -Math.log(duration ** 3 / vPeak ** 2 * jerkIntegral);
  }
  function sparc(speed, fs, padlevel = 4, fc = 10, ampTh = 0.05) {
    const nfft = 2 ** (Math.ceil(Math.log2(speed.length)) + padlevel);
    const f = arange(0, fs, fs / nfft);
    const Mf = fftMag(speed, nfft);
    const peak = maxOf(Mf);
    for (let i = 0; i < Mf.length; i++) Mf[i] /= peak;
    let last = -1;
    for (let i = 0; i < f.length; i++) if (f[i] <= fc) last = i;
    let lo = -1, hi = -1;
    for (let i = 0; i <= last; i++) if (Mf[i] >= ampTh) {
      if (lo < 0) lo = i;
      hi = i;
    }
    if (lo < 0 || hi - lo < 1) return NaN;
    const span = f[hi] - f[lo];
    let arc = 0;
    for (let i = lo; i < hi; i++) {
      arc += Math.hypot((f[i + 1] - f[i]) / span, Mf[i + 1] - Mf[i]);
    }
    return -arc;
  }
  function tremorResidual(x, y, fs, cutoff = 2) {
    const { b, a } = butter(2, cutoff, fs, "high");
    return filtfilt(b, a, hypot(x, y));
  }
  var _welch = (sig, fs) => welch(sig, fs, Math.min(sig.length, Math.trunc(fs * 4)));
  function bandPower(sig, fs, band) {
    const { freqs, psd } = _welch(sig, fs);
    const f = [], p = [];
    for (let i = 0; i < freqs.length; i++) {
      if (freqs[i] >= band[0] && freqs[i] <= band[1]) {
        f.push(freqs[i]);
        p.push(psd[i]);
      }
    }
    if (f.length < 2) return NaN;
    let area = 0;
    for (let i = 0; i < f.length - 1; i++) area += (p[i] + p[i + 1]) / 2 * (f[i + 1] - f[i]);
    return area;
  }
  function dominantFrequency(sig, fs, band = [3, 12]) {
    const { freqs, psd } = _welch(sig, fs);
    let best = -1, bestP = -Infinity;
    for (let i = 0; i < freqs.length; i++) {
      if (freqs[i] >= band[0] && freqs[i] <= band[1] && psd[i] > bestP) {
        bestP = psd[i];
        best = i;
      }
    }
    return best < 0 ? NaN : freqs[best];
  }
  function extractSpiralFeatures(t, x, y, fs = 100) {
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
      spiral_tremor_4_6: bandPower(residual, fs, [4, 6]),
      spiral_tremor_6_12: bandPower(residual, fs, [6, 12]),
      spiral_tremor_dominant_hz: dominantFrequency(residual, fs)
    };
  }
  function featuresFromTrace(trace, fs = 100) {
    if (trace.task !== "spiral") throw new Error(`no feature extractor for task ${trace.task}`);
    const t = Float64Array.from(trace.samples, (s) => s.t);
    const x = Float64Array.from(trace.samples, (s) => s.x);
    const y = Float64Array.from(trace.samples, (s) => s.y);
    const [pt, px, py] = preprocessTrace(t, x, y, fs);
    return extractSpiralFeatures(pt, px, py, fs);
  }
  var featureVector = (f) => SPIRAL_FEATURE_ORDER.map((k) => f[k]);

  // ../app/score.js
  var score_exports = {};
  __export(score_exports, {
    TIER_CUTS: () => TIER_CUTS,
    averageFeatures: () => averageFeatures,
    bracketFor: () => bracketFor,
    checkScoringFiles: () => checkScoringFiles,
    fractionBelow: () => fractionBelow,
    scoreSession: () => scoreSession
  });
  var TIER_CUTS = [0.75, 0.95];
  function checkScoringFiles(model, reference, featureOrder) {
    const order = featureOrder.join(",");
    const reExport = "Re-export with training/scripts/export_model.py.";
    if (model.version !== 2) {
      throw new Error(`model.json version is ${model.version}, expected 2. ${reExport}`);
    }
    if (!model.featureOrder || model.featureOrder.join(",") !== order) {
      throw new Error(
        `model.json featureOrder [${(model.featureOrder || []).join(", ")}] does not match the app's feature order [${featureOrder.join(", ")}]. ${reExport}`
      );
    }
    if (model.weights.length !== featureOrder.length) {
      throw new Error(
        `model.json weights has ${model.weights.length} entries, expected ${featureOrder.length}. ${reExport}`
      );
    }
    if (typeof model.bias !== "number") {
      throw new Error(`model.json bias is ${typeof model.bias}, expected a number. ${reExport}`);
    }
    if (reference.version !== 2) {
      throw new Error(`reference.json version is ${reference.version}, expected 2. ${reExport}`);
    }
    if (!reference.featureOrder || reference.featureOrder.join(",") !== order) {
      throw new Error(
        `reference.json featureOrder [${(reference.featureOrder || []).join(", ")}] does not match the app's feature order [${featureOrder.join(", ")}]. ${reExport}`
      );
    }
    if (!reference.brackets || !reference.brackets.all) {
      throw new Error(`reference.json is missing brackets.all. ${reExport}`);
    }
    for (const [key, block] of Object.entries(reference.brackets)) {
      if (block.mean.length !== featureOrder.length || block.sd.length !== featureOrder.length) {
        throw new Error(`reference.json brackets.${key} has a mean/sd of the wrong length. ${reExport}`);
      }
      for (const k of featureOrder) {
        if (!Array.isArray(block.features?.[k])) {
          throw new Error(`reference.json brackets.${key}.features is missing "${k}". ${reExport}`);
        }
      }
      if (!Array.isArray(block.score)) {
        throw new Error(`reference.json brackets.${key} is missing its score array. ${reExport}`);
      }
    }
  }
  function bracketFor(reference, bracketKey) {
    const key = bracketKey ?? "all";
    const block = reference.brackets[key];
    if (block && block.n >= reference.minBracketN) return { key, block };
    return { key: "all", block: reference.brackets.all };
  }
  function averageFeatures(perTrial, featureOrder) {
    const out = {};
    for (const k of featureOrder) {
      let sum = 0, n = 0;
      for (const trial of perTrial) {
        const v = trial[k];
        if (Number.isFinite(v)) {
          sum += v;
          n++;
        }
      }
      out[k] = n > 0 ? sum / n : NaN;
    }
    return out;
  }
  function fractionBelow(v, values) {
    let count = 0;
    for (const x of values) if (x < v) count++;
    return count / values.length;
  }
  function scoreSession(perTrial, model, reference, bracketKey) {
    const features = averageFeatures(perTrial, model.featureOrder);
    const { key, block } = bracketFor(reference, bracketKey);
    const weighted = model.featureOrder.map((k, i) => {
      const f = features[k];
      const sd = block.sd[i];
      const z = Number.isFinite(f) && sd > 0 && Number.isFinite(sd) ? (f - block.mean[i]) / sd : 0;
      return model.weights[i] * z;
    });
    const zsum = model.bias + weighted.reduce((a, b) => a + b, 0);
    const score = 1 / (1 + Math.exp(-zsum));
    const scorePct = fractionBelow(score, block.score);
    const tier = scorePct < TIER_CUTS[0] ? 0 : scorePct < TIER_CUTS[1] ? 1 : 2;
    const measurePct = {};
    model.featureOrder.forEach((k) => {
      if (Number.isFinite(features[k])) measurePct[k] = fractionBelow(features[k], block.features[k]);
    });
    const topSignals = model.featureOrder.map((k, i) => ({ k, signal: weighted[i] })).filter((s) => Number.isFinite(features[s.k])).sort((a, b) => b.signal - a.signal).slice(0, 3).map((s) => s.k);
    return {
      features,
      bracketKey: key,
      referenceN: block.n,
      deviceMatched: reference.deviceMatched === true,
      trialsPerSession: reference.trialsPerSession,
      tier,
      measurePct,
      topSignals,
      score,
      scorePct
    };
  }

  // ../app/train.js
  var train_exports = {};
  __export(train_exports, {
    BACK_LIMIT: () => BACK_LIMIT,
    BELOW_LIMIT: () => BELOW_LIMIT,
    CATCH_SHARE: () => CATCH_SHARE,
    CLOSE_DEPTH: () => CLOSE_DEPTH,
    COUNT_IN: () => COUNT_IN,
    COVER_PIECES: () => COVER_PIECES,
    EXERCISES: () => EXERCISES,
    HITS_TO_LEVEL_UP: () => HITS_TO_LEVEL_UP,
    HIT_SHARE: () => HIT_SHARE,
    MIN_LOOP: () => MIN_LOOP,
    MIN_LOOPS: () => MIN_LOOPS,
    MIN_STEP: () => MIN_STEP,
    MISSES_TO_LEVEL_DOWN: () => MISSES_TO_LEVEL_DOWN,
    OWN_REACH: () => OWN_REACH,
    REACH: () => REACH,
    RECENT_TRIES: () => RECENT_TRIES,
    RHYTHM_BEATS: () => RHYTHM_BEATS,
    RHYTHM_COVER: () => RHYTHM_COVER,
    RHYTHM_LAG: () => RHYTHM_LAG,
    RHYTHM_MIN_COVER: () => RHYTHM_MIN_COVER,
    RHYTHM_NEAR: () => RHYTHM_NEAR,
    RHYTHM_SHAKIER_LIMIT: () => RHYTHM_SHAKIER_LIMIT,
    SHAKIER_LIMIT: () => SHAKIER_LIMIT,
    SHRINK_SECS: () => SHRINK_SECS,
    SLOWER_LIMIT: () => SLOWER_LIMIT,
    STILL_PX: () => STILL_PX,
    TAP_PRECISION: () => TAP_PRECISION,
    TARGETS: () => TARGETS,
    TOUCH_PX: () => TOUCH_PX,
    TRACE_COVER: () => TRACE_COVER,
    TRACE_LIMIT: () => TRACE_LIMIT,
    TRACE_MIN_COVER: () => TRACE_MIN_COVER,
    TRACE_TURNS: () => TRACE_TURNS,
    WOBBLE_SECS: () => WOBBLE_SECS,
    applyTry: () => applyTry,
    compareRecent: () => compareRecent,
    findLoops: () => findLoops,
    makePath: () => makePath,
    motionMeasures: () => motionMeasures,
    nearestOnPath: () => nearestOnPath,
    newLevelState: () => newLevelState,
    pointAlong: () => pointAlong,
    reachesLine: () => reachesLine,
    rhythmPath: () => rhythmPath,
    scoreBigWriting: () => scoreBigWriting,
    scoreRhythm: () => scoreRhythm,
    scoreTargets: () => scoreTargets,
    scoreTracing: () => scoreTracing,
    targetRadius: () => targetRadius,
    tooHard: () => tooHard,
    tracingPath: () => tracingPath,
    trimStill: () => trimStill
  });
  var HITS_TO_LEVEL_UP = 3;
  var MISSES_TO_LEVEL_DOWN = 3;
  var SLOWER_LIMIT = 0.15;
  var SHAKIER_LIMIT = 0.15;
  var RECENT_TRIES = 5;
  var EXERCISES = {
    // target height as a share of the writing area's height.
    "big-writing": { built: true, levels: [0.2, 0.24, 0.28, 0.32, 0.36, 0.4, 0.45, 0.5, 0.55, 0.6] },
    // beats per minute.
    rhythm: { built: true, levels: [40, 45, 50, 55, 60, 66, 72, 80, 88, 96] },
    // how visible the guide is, 1 = fully.
    "steady-tracing": { built: true, levels: [1, 0.85, 0.7, 0.55, 0.45, 0.35, 0.25, 0.15, 0.08, 0] },
    // each target's starting width in CSS px.
    "hand-skills": { built: true, levels: [96, 84, 72, 64, 56, 48, 42, 36, 32, 28] }
  };
  var newLevelState = () => ({ level: 0, hits: 0, misses: 0, last: null });
  function applyTry(state, { counted, hit }, levelCount) {
    if (!counted) return { state, change: null };
    if (hit) {
      const hits = state.hits + 1;
      if (hits >= HITS_TO_LEVEL_UP && state.level < levelCount - 1) {
        return { state: { level: state.level + 1, hits: 0, misses: 0, last: "up" }, change: "up" };
      }
      return { state: { ...state, hits: Math.min(hits, HITS_TO_LEVEL_UP), misses: 0 }, change: null };
    }
    const misses = state.misses + 1;
    if (misses >= MISSES_TO_LEVEL_DOWN && state.level > 0) {
      return { state: { level: state.level - 1, hits: 0, misses: 0, last: "down" }, change: "down" };
    }
    return { state: { ...state, misses: Math.min(misses, MISSES_TO_LEVEL_DOWN) }, change: null };
  }
  function tooHard(state) {
    if (state.level === 0) return state;
    return { level: state.level - 1, hits: 0, misses: 0, last: "down" };
  }
  var median2 = (xs) => {
    if (!xs.length) return NaN;
    const s = [...xs].sort((a, b) => a - b), m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  };
  var mean2 = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
  var STILL_PX = 4;
  function trimStill(stroke) {
    const dist = (p, q) => Math.hypot(p.x - q.x, p.y - q.y);
    let a = 0, b = stroke.length - 1;
    while (a < b && dist(stroke[a + 1], stroke[0]) < STILL_PX) a++;
    while (b > a && dist(stroke[b - 1], stroke[stroke.length - 1]) < STILL_PX) b--;
    return stroke.slice(a, b + 1);
  }
  function motionMeasures(samples, strokeStarts = [0]) {
    const bounds = [...strokeStarts, samples.length];
    let penDown = 0, length = 0, peaks = 0;
    for (let s = 0; s < bounds.length - 1; s++) {
      const stroke = trimStill(samples.slice(bounds[s], bounds[s + 1]));
      if (stroke.length < 2) continue;
      penDown += stroke[stroke.length - 1].t - stroke[0].t;
      for (let i = 1; i < stroke.length; i++) {
        length += Math.hypot(stroke[i].x - stroke[i - 1].x, stroke[i].y - stroke[i - 1].y);
      }
      peaks += speedPeaks(stroke);
    }
    return { penDown, length, peaks };
  }
  function speedPeaks(stroke) {
    const t0 = stroke[0].t, t1 = stroke[stroke.length - 1].t, step = 1 / 60;
    const pts = [];
    let j = 0;
    for (let t = t0; t <= t1; t += step) {
      while (j < stroke.length - 2 && stroke[j + 1].t < t) j++;
      const a = stroke[j], b = stroke[j + 1];
      const f = b.t > a.t ? Math.min(1, Math.max(0, (t - a.t) / (b.t - a.t))) : 0;
      pts.push([a.x + f * (b.x - a.x), a.y + f * (b.y - a.y)]);
    }
    if (pts.length < 5) return 0;
    const raw = [];
    for (let i = 1; i < pts.length; i++) raw.push(Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]) / step);
    const speed = raw.map((_, i) => {
      const w = raw.slice(Math.max(0, i - 2), i + 3);
      return mean2(w);
    });
    const delta = 0.25 * median2(speed);
    if (!(delta > 0)) return 0;
    let count = 0, rising = true, best = -Infinity, low = Infinity;
    for (const v of speed) {
      if (rising) {
        if (v > best) best = v;
        else if (v < best - delta) {
          count++;
          rising = false;
          low = v;
        }
      } else if (v < low) low = v;
      else if (v > low + delta) {
        rising = true;
        best = v;
      }
    }
    return rising && best > low + delta ? count + 1 : count;
  }
  var REACH = 0.9;
  var OWN_REACH = 0.85;
  var HIT_SHARE = 0.75;
  var MIN_LOOPS = 4;
  var MIN_LOOP = 0.15;
  var MIN_STEP = 0.15;
  var CLOSE_DEPTH = 0.2;
  var TOUCH_PX = 1;
  var BACK_LIMIT = 0.05;
  var BACK_DEPTHS = [0.1, 0.2, 0.3];
  var BELOW_LIMIT = 0.25;
  function turningPoints(h, drop) {
    const out = [];
    let mode = 0, hi = 0, lo = 0;
    for (let i = 1; i < h.length; i++) {
      if (mode >= 0 && h[i] > h[hi]) hi = i;
      if (mode <= 0 && h[i] < h[lo]) lo = i;
      if (mode >= 0 && h[hi] - h[i] >= drop) {
        out.push({ i: hi, peak: true });
        mode = -1;
        lo = i;
      } else if (mode <= 0 && h[i] - h[lo] >= drop) {
        out.push({ i: lo, peak: false });
        mode = 1;
        hi = i;
      }
    }
    if (mode === 1 && out.length && h[hi] - h[out.at(-1).i] >= drop) out.push({ i: hi, peak: true });
    if (mode === -1) out.push({ i: lo, peak: false });
    return out;
  }
  function segmentsCross(p1, p2, p3, p4) {
    const side = (a, b, c) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    return side(p3, p4, p1) * side(p3, p4, p2) < 0 && side(p1, p2, p3) * side(p1, p2, p4) < 0;
  }
  function toSegment(p, a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy;
    const f = len2 ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0;
    return Math.hypot(p.x - a.x - f * dx, p.y - a.y - f * dy);
  }
  function segmentsMeet(p1, p2, p3, p4) {
    return segmentsCross(p1, p2, p3, p4) || Math.min(toSegment(p1, p3, p4), toSegment(p2, p3, p4), toSegment(p3, p1, p2), toSegment(p4, p1, p2)) <= TOUCH_PX;
  }
  function closesAround(samples, h, lifts, from, top, to, own) {
    const deep = h[top] - CLOSE_DEPTH * own;
    for (let i = from; i < top; i++) {
      if (lifts.has(i + 1)) continue;
      const ilo = Math.min(h[i], h[i + 1]), ihi = Math.max(h[i], h[i + 1]);
      if (ilo > deep) continue;
      for (let j = top; j < to; j++) {
        if (lifts.has(j + 1)) continue;
        const jlo = Math.min(h[j], h[j + 1]), jhi = Math.max(h[j], h[j + 1]);
        if (jlo > ihi + TOUCH_PX || ilo > jhi + TOUCH_PX) continue;
        if ((h[i] + h[i + 1] + h[j] + h[j + 1]) / 4 > deep) continue;
        if (segmentsMeet(samples[i], samples[i + 1], samples[j], samples[j + 1])) return true;
      }
    }
    return false;
  }
  function sidesAt(samples, h, from, top, to, level) {
    const at = (a, b) => {
      const f = h[b] === h[a] ? 0 : (level - h[a]) / (h[b] - h[a]);
      return samples[a].x + f * (samples[b].x - samples[a].x);
    };
    let d = top;
    while (d < to && h[d] > level) d++;
    let u = top;
    while (u > from && h[u] > level) u--;
    return { up: h[u] <= level && u < top ? at(u, u + 1) : null, down: h[d] <= level && d > top ? at(d - 1, d) : null };
  }
  function backSide(samples, h, from, top, to, own) {
    const gaps = [];
    for (const f of BACK_DEPTHS) {
      const { up, down } = sidesAt(samples, h, from, top, to, h[top] - f * own);
      if (up == null || down == null) return null;
      gaps.push((down - up) / own);
    }
    return mean2(gaps);
  }
  function findLoops(samples, baselineY, targetPx, strokeStarts = [0]) {
    if (samples.length < 2) return [];
    const h = samples.map((p) => baselineY - p.y);
    const drop = Math.max(6, MIN_LOOP * targetPx);
    const sorted = [...h].sort((p, q) => p - q);
    const base = sorted[Math.floor(0.1 * (sorted.length - 1))];
    const letters = [];
    let valley = null;
    for (const p of turningPoints(h, drop)) {
      if (!p.peak) {
        if (valley == null || h[p.i] < h[valley]) valley = p.i;
        continue;
      }
      const cur = letters.at(-1);
      if (cur && valley != null) {
        const lower = Math.min(h[cur.top], h[p.i]);
        const over = samples[p.i].x - samples[cur.top].x < MIN_STEP * (lower - h[valley]);
        if (over || lower - h[valley] < 0.5 * (lower - base)) {
          if (h[p.i] > h[cur.top]) cur.top = p.i;
          valley = null;
          continue;
        }
        cur.after = valley;
      }
      letters.push({ top: p.i, before: valley, after: null });
      valley = null;
    }
    if (letters.length) letters.at(-1).after = valley;
    const lifts = new Set(strokeStarts);
    return letters.map(({ top, before, after }) => {
      const from = before ?? 0, to = after ?? samples.length - 1;
      let bottom = Infinity;
      for (const i of [from, to]) bottom = Math.min(bottom, h[i]);
      const own = h[top] - bottom;
      const closed = closesAround(samples, h, lifts, from, top, to, own);
      const back = backSide(samples, h, from, top, to, own);
      const loop = closed || back != null && back <= BACK_LIMIT;
      return { i: top, top: h[top], own, bottom, closed, back, loop, x: samples[top].x, y: samples[top].y };
    }).filter((l) => l.own >= drop);
  }
  var reachesLine = (loop, targetPx) => loop.loop && loop.bottom >= -BELOW_LIMIT * targetPx && loop.top >= REACH * targetPx && loop.own >= OWN_REACH * targetPx;
  function compareRecent(measures, recent, peaksKey = "peaksPerLoop") {
    const prev = recent.slice(0, RECENT_TRIES);
    if (!prev.length) return { pace: null, smoothness: null };
    const known = (key) => prev.map((m) => m[key]).filter(Number.isFinite);
    const pace = median2(known("pace"));
    const peaks = median2(known(peaksKey));
    return {
      pace: pace > 0 ? measures.pace / pace - 1 : null,
      // lower = smoother, so the sign is flipped.
      smoothness: peaks > 0 ? 1 - measures[peaksKey] / peaks : null
    };
  }
  function judge(counted, reachedTarget, vs, measures, extra = {}, shakierLimit = SHAKIER_LIMIT) {
    const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
    const shakier = vs.smoothness != null && vs.smoothness < -shakierLimit;
    return { counted, reachedTarget, slower, shakier, hit: reachedTarget && !slower && !shakier, measures, vs, ...extra };
  }
  function scoreBigWriting(samples, strokeStarts, { baselineY, targetPx }, recent = []) {
    const found = findLoops(samples, baselineY, targetPx, strokeStarts);
    const tops = found.map((l) => l.own);
    const motion = motionMeasures(samples, strokeStarts);
    const loops = found.length;
    const reached = found.filter((l) => reachesLine(l, targetPx)).length;
    const third = Math.floor(loops / 3);
    const measures = {
      loops,
      reached,
      // letters shaped like a spike, hump or arch rather than a loop.
      open: found.filter((l) => !l.loop).length,
      // loops whose base dipped well below the baseline.
      below: found.filter((l) => l.loop && l.bottom < -BELOW_LIMIT * targetPx).length,
      // median loop height, from each loop's own bottom, as a share of the target height.
      size: loops ? median2(tops) / targetPx : NaN,
      // share of loops that touched the line.
      accuracy: loops ? reached / loops : NaN,
      // how much the last third of the row shrank (negative) or grew against the first third.
      shrink: third >= 2 ? mean2(tops.slice(-third)) / mean2(tops.slice(0, third)) - 1 : NaN,
      pace: motion.penDown > 0 ? loops / motion.penDown : NaN,
      peaksPerLoop: loops ? motion.peaks / loops : NaN
    };
    const counted = loops >= MIN_LOOPS && measures.pace > 0;
    const vs = counted ? compareRecent(measures, recent) : { pace: null, smoothness: null };
    const reachedTarget = counted && measures.accuracy >= HIT_SHARE;
    const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
    const shakier = vs.smoothness != null && vs.smoothness < -SHAKIER_LIMIT;
    const marks = found.map((l) => ({ x: l.x, y: l.y, reached: reachesLine(l, targetPx) }));
    return { counted, reachedTarget, slower, shakier, hit: reachedTarget && !slower && !shakier, measures, vs, marks };
  }
  function makePath(points) {
    const x = points.map((p) => p[0]), y = points.map((p) => p[1]), s = [0];
    for (let i = 1; i < points.length; i++) s.push(s[i - 1] + Math.hypot(x[i] - x[i - 1], y[i] - y[i - 1]));
    return { x, y, s, length: s[s.length - 1] };
  }
  function nearestOnPath(path, px, py) {
    let dist = Infinity, along = 0;
    for (let i = 1; i < path.x.length; i++) {
      const ax = path.x[i - 1], ay = path.y[i - 1], dx = path.x[i] - ax, dy = path.y[i] - ay;
      const len2 = dx * dx + dy * dy;
      const f = len2 ? Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / len2)) : 0;
      const d = Math.hypot(px - ax - f * dx, py - ay - f * dy);
      if (d < dist) {
        dist = d;
        along = path.s[i - 1] + f * Math.sqrt(len2);
      }
    }
    return { dist, along };
  }
  function pointAlong(path, along) {
    const a = Math.min(Math.max(along, 0), path.length);
    let i = 1;
    while (i < path.s.length - 1 && path.s[i] < a) i++;
    const span = path.s[i] - path.s[i - 1], f = span ? (a - path.s[i - 1]) / span : 0;
    return [path.x[i - 1] + f * (path.x[i] - path.x[i - 1]), path.y[i - 1] + f * (path.y[i] - path.y[i - 1])];
  }
  var COVER_PIECES = 40;
  function coverage(nearest, length, closePx) {
    const done = /* @__PURE__ */ new Set();
    for (const n of nearest) if (n.dist <= closePx) done.add(Math.min(COVER_PIECES - 1, Math.floor(n.along / length * COVER_PIECES)));
    return done.size / COVER_PIECES;
  }
  var TRACE_TURNS = 3;
  var TRACE_COVER = 0.9;
  var TRACE_LIMIT = 0.05;
  var TRACE_MIN_COVER = 0.5;
  function tracingPath(w, h) {
    const radius = Math.min(w, h) / 2 - 24, n = 600, pts = [];
    for (let i = 0; i <= n; i++) {
      const p = i / n, th = p * TRACE_TURNS * 2 * Math.PI;
      pts.push([w / 2 + p * radius * Math.cos(th), h / 2 + p * radius * Math.sin(th)]);
    }
    return { ...makePath(pts), radius };
  }
  function scoreTracing(samples, strokeStarts, path, recent = []) {
    const nearest = samples.map((p) => nearestOnPath(path, p.x, p.y));
    const cover = coverage(nearest, path.length, 0.12 * path.radius);
    const distPx = nearest.length ? mean2(nearest.map((n) => n.dist)) : NaN;
    const motion = motionMeasures(samples, strokeStarts);
    const turns = TRACE_TURNS * cover;
    const measures = {
      cover,
      distPx,
      // average distance from the guide as a share of the spiral's radius.
      accuracy: distPx / path.radius,
      // spiral radii traced per second, to make pace more comparable across canvas sizes.
      pace: motion.penDown > 0 ? cover * path.length / path.radius / motion.penDown : NaN,
      peaksPerTurn: turns > 0 ? motion.peaks / turns : NaN
    };
    const counted = cover >= TRACE_MIN_COVER && measures.pace > 0;
    const vs = counted ? compareRecent(measures, recent, "peaksPerTurn") : { pace: null, smoothness: null };
    return judge(counted, counted && cover >= TRACE_COVER && measures.accuracy <= TRACE_LIMIT, vs, measures, {
      limitPx: TRACE_LIMIT * path.radius
    });
  }
  var RHYTHM_BEATS = 8;
  var COUNT_IN = 3;
  var RHYTHM_COVER = 0.85;
  var RHYTHM_LAG = 0.5;
  var RHYTHM_NEAR = 0.25;
  var RHYTHM_MIN_COVER = 0.4;
  function rhythmPath(w, h) {
    const left = 0.08 * w, right = 0.92 * w, mid = h / 2, amp = 0.3 * h, n = 60 * RHYTHM_BEATS, pts = [];
    for (let i = 0; i <= n; i++) {
      const p = i / n;
      pts.push([left + p * (right - left), mid + amp * Math.cos(Math.PI * p * RHYTHM_BEATS)]);
    }
    const path = makePath(pts);
    return { ...path, height: 2 * amp, beatLength: path.length / RHYTHM_BEATS };
  }
  var WOBBLE_SECS = 0.25;
  var RHYTHM_SHAKIER_LIMIT = 0.5;
  function wobble(samples, strokeStarts, path, nearest, moving) {
    const side = samples.map((p, i) => {
      const a = pointAlong(path, nearest[i].along - 1), b = pointAlong(path, nearest[i].along + 1);
      return Math.sign((b[0] - a[0]) * (p.y - a[1]) - (b[1] - a[1]) * (p.x - a[0])) * nearest[i].dist;
    });
    const bounds = [...strokeStarts, samples.length];
    const half = Math.round(WOBBLE_SECS * 60 / 2);
    let sum = 0, count = 0;
    for (let k = 0; k < bounds.length - 1; k++) {
      const a = bounds[k], b = bounds[k + 1];
      if (b - a < 2) continue;
      const r = [], ts = [];
      let j = a;
      for (let t = samples[a].t; t <= samples[b - 1].t; t += 1 / 60) {
        while (j < b - 2 && samples[j + 1].t < t) j++;
        const p = samples[j], q = samples[j + 1];
        const f = q.t > p.t ? Math.min(1, Math.max(0, (t - p.t) / (q.t - p.t))) : 0;
        r.push(side[j] + f * (side[j + 1] - side[j]));
        ts.push(t);
      }
      for (let i = 0; i < r.length; i++) {
        if (!moving(ts[i])) continue;
        sum += (r[i] - mean2(r.slice(Math.max(0, i - half), i + half + 1))) ** 2;
        count++;
      }
    }
    return count ? Math.sqrt(sum / count) : NaN;
  }
  function scoreRhythm(samples, strokeStarts, path, { beatSec, penOffset }, recent = []) {
    const nearest = samples.map((p) => nearestOnPath(path, p.x, p.y));
    const end = RHYTHM_BEATS * beatSec;
    const lags = [];
    samples.forEach((p, i) => {
      const t = p.t + penOffset;
      if (t < 0 || t > end) return;
      lags.push(nearest[i].along / path.beatLength - t / beatSec);
    });
    const cover = coverage(nearest, path.length, 0.2 * path.height);
    const motion = motionMeasures(samples, strokeStarts);
    const beats = RHYTHM_BEATS * cover;
    const moving = (t) => t + penOffset >= 0 && t + penOffset <= end;
    const measures = {
      cover,
      // how far from the dot, in beats, ignoring ahead or behind.
      lag: lags.length ? mean2(lags.map(Math.abs)) : NaN,
      // the same with its sign: + ahead of the dot, - behind.
      lead: lags.length ? mean2(lags) : NaN,
      near: nearest.length ? mean2(nearest.map((n) => n.dist)) / path.height : NaN,
      peaksPerBeat: beats > 0 ? motion.peaks / beats : NaN,
      // side-to-side wobble while the dot moved, CSS px (see WOBBLE_SECS).
      wobble: wobble(samples, strokeStarts, path, nearest, moving)
    };
    const counted = cover >= RHYTHM_MIN_COVER && lags.length >= 10;
    const vs = counted ? { pace: null, smoothness: compareRecent(measures, recent, "wobble").smoothness } : { pace: null, smoothness: null };
    const reached = counted && cover >= RHYTHM_COVER && measures.lag <= RHYTHM_LAG && measures.near <= RHYTHM_NEAR;
    return judge(counted, reached, vs, measures, {}, RHYTHM_SHAKIER_LIMIT);
  }
  var TARGETS = 15;
  var SHRINK_SECS = 2;
  var CATCH_SHARE = 0.8;
  var TAP_PRECISION = 0.8;
  var targetRadius = (startSize, secs) => Math.max(0, startSize / 2 * (1 - secs / SHRINK_SECS));
  function scoreTargets(results, extraTaps) {
    const caught = results.filter((r) => r.caught);
    const measures = {
      targets: results.length,
      caught: caught.length,
      extraTaps,
      reactionMs: caught.length ? median2(caught.map((r) => r.ms)) : NaN,
      // share of all taps that caught a circle.
      precision: caught.length + extraTaps ? caught.length / (caught.length + extraTaps) : 0
    };
    const counted = results.length >= TARGETS;
    const reached = counted && caught.length / results.length >= CATCH_SHARE && measures.precision >= TAP_PRECISION;
    return judge(counted, reached, { pace: null, smoothness: null }, measures);
  }

  // ../app/tapping.js
  var tapping_exports = {};
  __export(tapping_exports, {
    MAX_HOLE: () => MAX_HOLE,
    MIN_SWING: () => MIN_SWING,
    MIN_TAPS: () => MIN_TAPS,
    TAP_HIGH: () => TAP_HIGH,
    TAP_LOW: () => TAP_LOW,
    TRIM: () => TRIM,
    analyzeTaps: () => analyzeTaps
  });
  var TAP_LOW = 0.2;
  var TAP_HIGH = 0.4;
  var TRIM = 0.05;
  var MAX_HOLE = 0.2;
  var MIN_TAPS = 5;
  var MIN_SWING = 0.25;
  var mean3 = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
  function quantile(xs, q) {
    const s = [...xs].sort((a, b) => a - b);
    const pos = q * (s.length - 1);
    const i = Math.floor(pos);
    return s[i] + (s[Math.ceil(pos)] - s[i]) * (pos - i);
  }
  function thirds(xs) {
    const k = Math.floor(xs.length / 3);
    return k ? [mean3(xs.slice(0, k)), mean3(xs.slice(-k))] : null;
  }
  function analyzeTaps({ samples = [] }) {
    const segments = [];
    let last = null;
    for (const s of samples) {
      if (s.gap == null || !Number.isFinite(s.gap)) continue;
      if (!last || s.t - last.t > MAX_HOLE) segments.push([]);
      segments[segments.length - 1].push(s);
      last = s;
    }
    const smoothed = segments.map(
      (seg) => seg.map((s, i) => ({ t: s.t, gap: mean3(seg.slice(Math.max(0, i - 1), i + 2).map((n2) => n2.gap)) }))
    );
    const gaps = smoothed.flat().map((s) => s.gap);
    const min = quantile(gaps, TRIM);
    const max = quantile(gaps, 1 - TRIM);
    const lo = min + TAP_LOW * (max - min);
    const hi = min + TAP_HIGH * (max - min);
    const moved = max - min >= MIN_SWING;
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
    const m = intervals.length ? mean3(intervals) : null;
    const usual = intervals.length ? quantile(intervals, 0.5) : null;
    const opening = thirds(openings);
    const speed = thirds(intervals);
    return {
      counted: n >= MIN_TAPS,
      taps: n,
      duration,
      rate: duration ? intervals.length / duration : null,
      // gaps between taps per second, like training's tap_rate
      rhythmCv: intervals.length >= 2 ? Math.sqrt(mean3(intervals.map((d) => (d - m) ** 2))) / m : null,
      meanOpening: n ? mean3(openings) : null,
      openingChange: opening && opening[1] / opening[0] - 1,
      // last third vs first third, -0.18 = 18% smaller
      rateChange: speed && speed[0] / speed[1] - 1,
      // same for speed, negative = slowed down
      pauses: intervals.filter((d) => d > 2 * usual).length,
      // a gap over twice the usual one
      tapTimes,
      openings
    };
  }

  // ../app/homescan.js
  var homescan_exports = {};
  __export(homescan_exports, {
    BANNED: () => BANNED,
    LIMITS: () => LIMITS,
    MAX_IDEAS: () => MAX_IDEAS,
    PRIORITIES: () => PRIORITIES,
    cleanIdeas: () => cleanIdeas
  });
  var MAX_IDEAS = 6;
  var LIMITS = { title: 80, why: 200, where: 80, room: 40 };
  var PRIORITIES = ["high", "medium", "low"];
  var BANNED = /\b(ensur\w*|guarantee\w*|detect\w*|diagnos\w*|screening|treat(s|ed|ing|ment)?|cur(e|es|ed|ing)|prevent\w*|slows|improv\w*|prov(e|es|en|ing)|accurate\w*|effective\w*|safe|safer|safest|safely|fall-?proof|inspection|parkinson\w*)\b/i;
  function parse(raw) {
    if (typeof raw !== "string") return raw;
    try {
      return JSON.parse(raw.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, ""));
    } catch {
      return null;
    }
  }
  function clip(text, max) {
    const s = typeof text === "string" ? text.replace(/\s+/g, " ").trim() : "";
    if (s.length <= max) return s;
    const i = s.lastIndexOf(" ", max - 1);
    return (i > 0 ? s.slice(0, i) : s.slice(0, max - 1)) + "\u2026";
  }
  function cleanIdeas({ raw, max = MAX_IDEAS }) {
    const data = parse(raw);
    if (!data || typeof data !== "object") return { status: "unreadable", room: "", ideas: [], dropped: 0 };
    const room = clip(data.room, LIMITS.room);
    if (data.isRoom === false) return { status: "notRoom", room, ideas: [], dropped: 0 };
    const list = Array.isArray(data.ideas) ? data.ideas : [];
    const seen = /* @__PURE__ */ new Set();
    const ideas = [];
    for (const item of list) {
      if (!item || typeof item.title !== "string") continue;
      const priority = String(item.priority).toLowerCase();
      const idea = {
        title: clip(item.title, LIMITS.title),
        why: clip(item.why, LIMITS.why),
        where: clip(item.where, LIMITS.where),
        priority: PRIORITIES.includes(priority) ? priority : "medium",
        done: false
      };
      const key = idea.title.toLowerCase().replace(/[^a-z0-9]/g, "");
      if (!key || seen.has(key) || BANNED.test(`${idea.title} ${idea.why} ${idea.where}`)) continue;
      seen.add(key);
      ideas.push(idea);
    }
    const kept2 = ideas.slice(0, max);
    return { status: kept2.length ? "ok" : "empty", room, ideas: kept2, dropped: list.length - kept2.length };
  }

  // ../app/meds.js
  var meds_exports = {};
  __export(meds_exports, {
    MIN_CHECKINS: () => MIN_CHECKINS,
    doseTiming: () => doseTiming,
    groupByHoursSinceDose: () => groupByHoursSinceDose,
    highestBin: () => highestBin,
    hoursSinceDose: () => hoursSinceDose
  });
  var HOUR_MS = 36e5;
  var MIN_CHECKINS = 6;
  function hoursSinceDose({ ts, doses, maxHours = 12 }) {
    let latest = null;
    for (const dose of doses) {
      if (dose.ts <= ts && (latest === null || dose.ts > latest)) latest = dose.ts;
    }
    if (latest === null) return null;
    const hours = (ts - latest) / HOUR_MS;
    return hours > maxHours ? null : hours;
  }
  function median3(values) {
    const sorted = [...values].sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
  function groupByHoursSinceDose({ checkins, doses, measure, edges = [0, 1, 2, 3, 4, 6, 12] }) {
    const maxHours = edges[edges.length - 1];
    const bins = edges.slice(0, -1).map((from, i) => ({ from, to: edges[i + 1], values: [] }));
    for (const checkin of checkins) {
      const value = checkin.measurePct?.[measure];
      if (!Number.isFinite(value)) continue;
      const hours = hoursSinceDose({ ts: checkin.ts, doses, maxHours });
      if (hours === null) continue;
      const bin = bins.find((b, i) => hours >= b.from && (hours < b.to || i === bins.length - 1));
      if (bin) bin.values.push(value);
    }
    return bins.map(({ from, to, values }) => ({
      from,
      to,
      n: values.length,
      median: values.length ? median3(values) : null
    }));
  }
  function highestBin({ bins, minN = 2 }) {
    let best = null;
    for (const bin of bins) {
      if (bin.n < minN || bin.median === null) continue;
      if (best === null || bin.median > best.median) best = bin;
    }
    return best;
  }
  function doseTiming({ checkins, doses, measure, hand = null, inputType = null }) {
    const same = checkins.filter(
      (c) => (hand === null || c.hand === hand) && (inputType === null || c.inputType === inputType)
    );
    const bins = groupByHoursSinceDose({ checkins: same, doses, measure });
    const counted = bins.reduce((sum, bin) => sum + bin.n, 0);
    const best = highestBin({ bins });
    return { ready: counted >= MIN_CHECKINS && best !== null, counted, bins, best };
  }

  // ../app/hands.js
  var hands_exports = {};
  __export(hands_exports, {
    compareHands: () => compareHands,
    latestPair: () => latestPair
  });
  var DAY_MS = 864e5;
  function latestPair({ records, maxDaysApart = 7 }) {
    let best = null;
    for (const left of records) {
      if (left.hand !== "left") continue;
      for (const right of records) {
        if (right.hand !== "right" || right.inputType !== left.inputType) continue;
        if (Math.abs(left.ts - right.ts) > maxDaysApart * DAY_MS) continue;
        const older = Math.min(left.ts, right.ts);
        const newer = Math.max(left.ts, right.ts);
        if (best === null || older > best.older || older === best.older && newer > best.newer) {
          best = { left, right, older, newer };
        }
      }
    }
    return best && { left: best.left, right: best.right };
  }
  function compareHands({ left, right, order = SPIRAL_FEATURE_ORDER }) {
    return order.filter((key) => Number.isFinite(left.measurePct?.[key]) && Number.isFinite(right.measurePct?.[key])).map((key) => {
      const l = left.measurePct[key];
      const r = right.measurePct[key];
      return { key, left: l, right: r, diff: l - r };
    }).sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
  }

  // js/core.js
  var helpers = {
    isBanned: (text) => BANNED.test(text)
  };
  var modules = { features: nt_features_exports, score: score_exports, train: train_exports, tapping: tapping_exports, homescan: homescan_exports, meds: meds_exports, hands: hands_exports, helpers };
  var NAN = "__ntNaN";
  var INF = "__ntInf";
  var NEG_INF = "__ntNegInf";
  var kept = /* @__PURE__ */ new Map();
  var nextKept = 1;
  var MAX_KEPT = 32;
  function revive(key, value) {
    if (value === NAN) return NaN;
    if (value === INF) return Infinity;
    if (value === NEG_INF) return -Infinity;
    if (value !== null && typeof value === "object" && typeof value.__ntRef === "number") return kept.get(value.__ntRef);
    return value;
  }
  function replace(key, value) {
    if (typeof value === "number" && !Number.isFinite(value)) return Number.isNaN(value) ? NAN : value > 0 ? INF : NEG_INF;
    if (ArrayBuffer.isView(value)) return Array.from(value);
    return value;
  }
  function find(path) {
    let value = modules;
    for (const part of path.split(".")) {
      if (value === void 0 || value === null || !(part in Object(value))) throw new Error(`NT has no ${path}`);
      value = value[part];
    }
    return value;
  }
  function run(path, argsJSON) {
    const target = find(path);
    return typeof target === "function" ? target(...JSON.parse(argsJSON, revive)) : target;
  }
  function call(path, argsJSON) {
    const value = run(path, argsJSON);
    return JSON.stringify({ v: value === void 0 ? null : value }, replace);
  }
  function callKeep(path, argsJSON) {
    const value = run(path, argsJSON);
    const ref = nextKept++;
    kept.set(ref, value);
    if (kept.size > MAX_KEPT) kept.delete(kept.keys().next().value);
    return JSON.stringify({ v: value, ref }, replace);
  }
  return __toCommonJS(core_exports);
})();
