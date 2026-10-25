// Simulated handwriting for testing train.js - rows of cursive l's and of test letter shapes
// Small random jitter from a fixed seed, the same samples on every run

// Mulberry32 - repeatable random numbers from a seed. Adapted from https://stackoverflow.com/a/47593316/1036426
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// A row of cursive l's. slant is x shift per px of height, sizeVar a random loop-to-loop size change
// (0.1 = +-10%), shrinkBy how much smaller the last loop is, liftEvery a pen lift every k loops, floatPx
// px above the baseline, rest seconds of still pen before and after, jerky speed swings in each loop (0 to 1)
export function cursiveRow({
  n = 8, height = 120, loopSecs = 0.7, baselineY = 300, x0 = 30, slant = 0.25, jitter = 0.3,
  sizeVar = 0.05, shrinkBy = 0, liftEvery = 0, floatPx = 0, rest = 0, jerky = 0, hz = 240, seed = 1,
} = {}) {
  const rand = rng(seed);
  const samples = [];
  const strokeStarts = [0];
  const dt = 1 / hz;
  let t = 0;
  let x = x0;
  const point = (px, py) => {
    const jx = (rand() - 0.5) * 2 * jitter;
    const jy = (rand() - 0.5) * 2 * jitter;
    samples.push({ t, x: px + jx, y: py + jy });
  };
  const base = baselineY - floatPx;
  for (let r = 0; r < rest; r += dt) {
    point(x, base);
    t += dt;
  }
  for (let k = 0; k < n; k++) {
    const shrink = 1 - shrinkBy * (k / Math.max(1, n - 1));
    const vary = 1 + (rand() - 0.5) * 2 * sizeVar;
    const H = height * shrink * vary;
    const c = (0.45 * H) / (2 * Math.PI);
    const w = 1.7 * c;
    const steps = Math.round(loopSecs * hz);
    for (let s = 0; s < steps; s++) {
      const u = s / steps;
      const warp = jerky * Math.sin(2 * Math.PI * 3 * u) / (2 * Math.PI * 3);
      const th = 2 * Math.PI * (u + warp);
      // Varies the speed within each loop without changing its duration
      const h = H * (1 - Math.cos(th)) / 2;
      point(x + c * th + w * Math.sin(th) + slant * h, base - h);
      t += dt;
    }
    x += 2 * Math.PI * c;
    if (liftEvery && (k + 1) % liftEvery === 0 && k < n - 1) {
      t += 0.35;
      strokeStarts.push(samples.length);
    }
  }
  for (let r = 0; r < rest; r += dt) {
    point(x, base);
    t += dt;
  }
  return { samples, strokeStarts };
}

// ---------- letter shapes, for testing what counts as a loop ----------
export const SHAPES = {
  closedL: { loop: true, pts: [[0, 0], [0.3, 0.35], [0.5, 0.75], [0.42, 1], [0.3, 0.8], [0.3, 0.4], [0.42, 0.05], [0.6, 0]] },
  // A closed cursive l - up the right, over the top, down the left, crossing
  narrowL: { loop: true, pts: [[0, 0], [0.22, 0.38], [0.38, 0.68], [0.41, 1], [0.4, 0.68], [0.41, 0.3], [0.45, 0.05], [0.62, 0]] },
  // A narrow l - up on a slant to the stem, up the stem and straight back down it
  retrace: { loop: true, pts: [[0, 0], [0.25, 0.5], [0.45, 1], [0.32, 0.55], [0.2, 0.2], [0.3, 0.03], [0.55, 0]] },
  // An l written back down along its up-stroke, a little behind it, never crossing
  eLoop: { loop: true, pts: [[0, 0.25], [0.3, 0.45], [0.4, 0.8], [0.28, 1], [0.12, 0.85], [0.08, 0.45], [0.2, 0.05], [0.6, 0]] },
  // An e - in low from the left, up and back over the top, down behind, crossing the way in
  curl: { loop: false, pts: [[0, 0], [0.3, 0.55], [0.42, 0.88], [0.5, 1], [0.58, 0.95], [0.55, 0.88], [0.48, 0.92], [0.55, 0.6], [0.75, 0]] },
  // A tent with a small curl at its top
  tooth: { loop: false, pts: [[0, 0], [0.2, 0.45], [0.4, 1], [0.41, 0.5], [0.43, 0.08], [0.6, 0]] },
  // A tooth - up on a slant, straight down
  spike: { loop: false, pts: [[0, 0], [0.32, 1], [0.6, 0]] },
  // A spike - straight up and straight down, forward
  hump: { loop: false, pts: [[0, 0], [0.2, 0.75], [0.4, 1], [0.6, 0.75], [0.8, 0]] },
  // A round hump
  nArch: { loop: false, pts: [[0, 0], [0.05, 0.9], [0.25, 1], [0.5, 0.9], [0.55, 0]] },
  // An n - up, across the top, down
};
// Control points in letter-height units: x right, h up
// Shapes with loop: true must count as loops, the rest must not

// Uniform Catmull-Rom curve through the points, perSeg samples per segment
function catmull(pts, perSeg) {
  const P = [pts[0], ...pts, pts.at(-1)];
  const out = [];
  for (let i = 1; i < P.length - 2; i++) {
    const [p0, p1, p2, p3] = [P[i - 1], P[i], P[i + 1], P[i + 2]];
    for (let s = 0; s < perSeg; s++) {
      const u = s / perSeg;
      const u2 = u * u;
      const u3 = u2 * u;
      const point = [0, 1].map((k) => {
        const a = 2 * p1[k];
        const b = (-p0[k] + p2[k]) * u;
        const c = (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2;
        const d = (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * u3;
        return 0.5 * (a + b + c + d);
      });
      out.push(point);
    }
  }
  out.push(pts.at(-1));
  return out;
}

// A row of SHAPES letters on the baseline. letters holds shape names or { shape, height, drop }
// A drop moves a letter's base below the baseline in px. Speed is in letter-heights per second
export function letterRow(letters, {
  height = 120, baselineY = 300, x0 = 30, slant = 0.2, speed = 3, jitter = 0.4, hz = 120, seed = 1, widthScale = 1,
} = {}) {
  const rand = rng(seed);
  const samples = [];
  let x = x0;
  let t = 0;
  for (const spec of letters) {
    const opts = typeof spec === "string" ? { shape: spec } : spec;
    const { shape, height: H = height, drop = 0 } = opts;
    const pts = SHAPES[shape].pts.map(([px, ph]) => [px * widthScale, ph]);
    const curve = catmull(pts, 24);
    for (let i = 0; i < curve.length; i++) {
      const [px, ph] = curve[i];
      if (i) {
        const [qx, qh] = curve[i - 1];
        t += Math.hypot(px - qx, ph - qh) / speed;
      }
      if (!samples.length || t - samples.at(-1).t >= 1 / hz) {
        const jx = (rand() - 0.5) * 2 * jitter;
        const jy = (rand() - 0.5) * 2 * jitter;
        samples.push({ t, x: x + (px + slant * ph) * H + jx, y: baselineY + drop - ph * H + jy });
      }
    }
    x += pts.at(-1)[0] * H;
  }
  return { samples, strokeStarts: [0] };
}

// The same writing as a mouse reports it - whole-pixel positions, one sample per pixel moved
export function mouseLike({ samples, strokeStarts = [0] }) {
  const lifts = new Set(strokeStarts);
  const out = [];
  const starts = [];
  for (let i = 0; i < samples.length; i++) {
    const b = samples[i];
    const lift = lifts.has(i);
    const a = lift ? b : samples[i - 1];
    if (lift) starts.push(out.length);
    const n = Math.max(1, Math.ceil(Math.hypot(b.x - a.x, b.y - a.y)));
    const first = lift ? n : 1;
    for (let k = first; k <= n; k++) {
      const p = {
        t: a.t + ((b.t - a.t) * k) / n,
        x: Math.round(a.x + ((b.x - a.x) * k) / n),
        y: Math.round(a.y + ((b.y - a.y) * k) / n),
      };
      const q = out.at(-1);
      const moved = !q || q.x !== p.x || q.y !== p.y;
      if (lift || moved) {
        out.push(p);
      }
    }
  }
  return { samples: out, strokeStarts: starts };
}
