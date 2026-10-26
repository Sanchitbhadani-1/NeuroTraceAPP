// NT-SIGNAL.JS HOLDS THE NUMBER TOOLS THE SPIRAL MEASUREMENTS ARE BUILT FROM, MATCHED TO NUMPY AND SCIPY
// EVERY FUNCTION HERE HAS A PYTHON VERSION THAT THE PARITY TEST COMPARES IT WITH
// IF ONE OF THEM CHANGES, THE OTHER HAS TO CHANGE TOO, AND TOOLS/PARITY.MJS HAS TO BE RUN AGAIN


// THE BASICS

// Find the average of a list of numbers
export function mean(v) {
  let total = 0;
  for (let i = 0; i < v.length; i++) {
    total += v[i];
  }
  return total / v.length;
}


// Find the largest number in a list
// Math.max(...v) runs out of call stack somewhere past about 100,000 numbers, and the FFT buffers are bigger than that
// So an array is never spread into Math.max here
export function maxOf(v) {
  let m = -Infinity;
  for (let i = 0; i < v.length; i++) {
    if (v[i] > m) {
      m = v[i];
    }
  }
  return m;
}


// Find the middle value of a list of numbers
export function median(v) {
  const s = Float64Array.from(v).sort();
  const m = Math.floor(s.length / 2);

  // An odd count has one middle value, and an even count averages the two in the middle
  if (s.length % 2) {
    return s[m];
  }
  return (s[m - 1] + s[m]) / 2;
}


// Find the length of each (a, b) pair, like Math.hypot for whole lists
export function hypot(a, b) {
  const out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) {
    out[i] = Math.hypot(a[i], b[i]);
  }
  return out;
}


// Make the numbers from start up to stop, step apart, like np.arange
// The count is rounded up, and stop itself is left out
export function arange(start, stop, step) {
  const n = Math.max(0, Math.ceil((stop - start) / step));
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = start + i * step;
  }
  return out;
}


// Find the value at each point of xNew by drawing straight lines between the points of xp and fp, like np.interp
// Points outside the range get the value at the nearest end
export function interp(xNew, xp, fp) {
  const out = new Float64Array(xNew.length);
  let j = 0;
  for (let i = 0; i < xNew.length; i++) {
    const v = xNew[i];

    // Before the first point or after the last one, use the value at that end
    if (v <= xp[0]) {
      out[i] = fp[0];
      continue;
    }
    if (v >= xp[xp.length - 1]) {
      out[i] = fp[fp.length - 1];
      continue;
    }

    // Move j to the piece that v falls in
    while (j < xp.length - 2 && xp[j + 1] < v) {
      j++;
    }
    while (j > 0 && xp[j] > v) {
      j--;
    }

    // Go the right share of the way along that piece
    const w = (v - xp[j]) / (xp[j + 1] - xp[j]);
    out[i] = fp[j] + w * (fp[j + 1] - fp[j]);
  }
  return out;
}


// Take out the jumps of a full turn in a list of angles, like np.unwrap
export function unwrap(p) {
  const out = Float64Array.from(p);
  let corr = 0;
  for (let i = 1; i < out.length; i++) {

    // A jump of more than half a turn is the angle wrapping around, so undo it
    const d = p[i] - p[i - 1];
    if (d > Math.PI) {
      corr -= 2 * Math.PI;
    } else if (d < -Math.PI) {
      corr += 2 * Math.PI;
    }
    out[i] = p[i] + corr;
  }
  return out;
}


// Find how fast f changes against t, like np.gradient(f, t) with edge_order=1
// It is centered and second order inside, and one sided at the ends
// It works for uneven t, even though ours is even after resampling
export function gradient(f, t) {
  const n = f.length;
  const out = new Float64Array(n);

  // The two ends only look at their one neighbor
  out[0] = (f[1] - f[0]) / (t[1] - t[0]);
  out[n - 1] = (f[n - 1] - f[n - 2]) / (t[n - 1] - t[n - 2]);

  // Every other point looks at both neighbors, weighted by how far away each one is
  for (let i = 1; i < n - 1; i++) {
    const d1 = t[i] - t[i - 1];
    const d2 = t[i + 1] - t[i];
    out[i] = (-d2 / (d1 * (d1 + d2))) * f[i - 1]
           + ((d2 - d1) / (d1 * d2)) * f[i]
           + (d1 / (d2 * (d1 + d2))) * f[i + 1];
  }
  return out;
}


// SMALL MATRIX MATH

// Solve A x = b with Gaussian elimination and partial pivoting, where n is small, 4 or less here
export function solve(A, b) {
  const n = b.length;

  // Put b on the end of each row of A
  const M = [];
  for (let i = 0; i < A.length; i++) {
    M.push([...A[i], b[i]]);
  }

  for (let c = 0; c < n; c++) {

    // Swap in the row with the biggest number in this column
    let p = c;
    for (let r = c + 1; r < n; r++) {
      if (Math.abs(M[r][c]) > Math.abs(M[p][c])) {
        p = r;
      }
    }
    const row = M[c];
    M[c] = M[p];
    M[p] = row;

    // Clear this column out of every other row
    for (let r = 0; r < n; r++) {
      if (r === c) {
        continue;
      }
      const k = M[r][c] / M[c][c];
      for (let j = c; j <= n; j++) {
        M[r][j] -= k * M[c][j];
      }
    }
  }

  // Each answer is its row's last number over its row's diagonal number
  const x = [];
  for (let i = 0; i < M.length; i++) {
    x.push(M[i][n] / M[i][i]);
  }
  return x;
}


// Find the least squares fit of y to the columns, using the normal equations
// This is fine for the 4 well scaled columns used here, but shouldn't be used with a nearly singular design matrix
export function lstsq(cols, y) {
  const k = cols.length;

  // Make AtA, the columns times each other, and Aty, the columns times y
  const AtA = [];
  for (let i = 0; i < k; i++) {
    AtA.push(new Array(k).fill(0));
  }
  const Aty = new Array(k).fill(0);

  for (let i = 0; i < k; i++) {

    // AtA is symmetric, so each pair is worked out once and put in both places
    for (let j = i; j < k; j++) {
      let s = 0;
      for (let m = 0; m < y.length; m++) {
        s += cols[i][m] * cols[j][m];
      }
      AtA[j][i] = s;
      AtA[i][j] = s;
    }

    let s = 0;
    for (let m = 0; m < y.length; m++) {
      s += cols[i][m] * y[m];
    }
    Aty[i] = s;
  }

  return solve(AtA, Aty);
}


// THE FFT

// Turn re and im into their FFT in place, with the radix 2 Cooley-Tukey method, where the length has to be a power of two
export function fft(re, im) {
  const n = re.length;

  // Put the numbers in bit reversed order, where j is always i with its bits reversed
  let j = 0;
  for (let i = 1; i < n; i++) {

    // Add one to j from the top bit down, carrying like adding in binary
    let bit = n >> 1;
    while (j & bit) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;

    // Swap each pair once
    if (i < j) {
      const tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      const ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  // Join the small transforms into bigger ones, doubling the length each time
  for (let len = 2; len <= n; len *= 2) {
    const half = len / 2;
    const ang = -2 * Math.PI / len;
    const wr = Math.cos(ang);
    const wi = Math.sin(ang);

    for (let i = 0; i < n; i += len) {

      // cr and ci are the cos and sin of the turn for this k, which steps by ang each time
      let cr = 1;
      let ci = 0;
      for (let k = 0; k < half; k++) {

        // Combine one number from the first half with its partner from the second half
        const ur = re[i + k];
        const ui = im[i + k];
        const vr = re[i + k + half] * cr - im[i + k + half] * ci;
        const vi = re[i + k + half] * ci + im[i + k + half] * cr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + half] = ur - vr;
        im[i + k + half] = ui - vi;

        // Step the turn on by ang
        const ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}


// Find the size of the first nfft / 2 + 1 bins, which is what np.fft.rfft gives
export function rfftMag(x, nfft) {
  const re = new Float64Array(nfft);
  const im = new Float64Array(nfft);

  // Copy in the first nfft numbers, using subarray for typed arrays and slice for plain ones
  if (x.subarray) {
    re.set(x.subarray(0, Math.min(x.length, nfft)));
  } else {
    re.set(x.slice(0, nfft));
  }

  fft(re, im);
  const out = new Float64Array(nfft / 2 + 1);
  for (let i = 0; i < out.length; i++) {
    out[i] = Math.hypot(re[i], im[i]);
  }
  return out;
}


// Find the size of every bin, like np.abs(np.fft.fft(x, nfft))
export function fftMag(x, nfft) {
  const re = new Float64Array(nfft);
  const im = new Float64Array(nfft);

  // Copy in the first nfft numbers, and leave the rest as 0
  const count = Math.min(x.length, nfft);
  for (let i = 0; i < count; i++) {
    re[i] = x[i];
  }

  fft(re, im);
  const out = new Float64Array(nfft);
  for (let i = 0; i < nfft; i++) {
    out[i] = Math.hypot(re[i], im[i]);
  }
  return out;
}