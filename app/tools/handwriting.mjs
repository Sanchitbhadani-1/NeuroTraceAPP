// simulated handwriting for testing train.js (a row of cursive l's).
// uses 240 Hz by default with small random jitter. a fixed seed makes
// the generated data repeatable.

// Mulberry32: repeatable random numbers from a seed. This was adapted from https://stackoverflow.com/a/47593316/1036426
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

// height: loop height in px. loopSecs: time per loop. slant: forward lean
// (x shift per px of height). sizeVar: random loop-to-loop size change
// (0.1 = +-10%). shrinkBy: the last loop is this much smaller than the first.
// liftEvery: lift the pen after every k loops. floatPx: writes this far above
// the drawn baseline. rest: seconds the pen sits still before and after.
// jerky: speed swings within each loop (stop-start movement), 0..1.
export function cursiveRow({
  n = 8, height = 120, loopSecs = 0.7, baselineY = 300, x0 = 30, slant = 0.25, jitter = 0.3,
  sizeVar = 0.05, shrinkBy = 0, liftEvery = 0, floatPx = 0, rest = 0, jerky = 0, hz = 240, seed = 1,
} = {}) {
  const rand = rng(seed);
  const samples = [], strokeStarts = [0];
  const dt = 1 / hz;
  let t = 0, x = x0;
  const point = (px, py) => samples.push({ t, x: px + (rand() - 0.5) * 2 * jitter, y: py + (rand() - 0.5) * 2 * jitter });
  const base = baselineY - floatPx;
  for (let r = 0; r < rest; r += dt) { point(x, base); t += dt; }
  for (let k = 0; k < n; k++) {
    const H = height * (1 - shrinkBy * (k / Math.max(1, n - 1))) * (1 + (rand() - 0.5) * 2 * sizeVar);
    const c = (0.45 * H) / (2 * Math.PI), w = 1.7 * c; // forward advance, loop width
    const steps = Math.round(loopSecs * hz);
    for (let s = 0; s < steps; s++) {
      const u = s / steps;
      // varies the speed within each loop without changing its overall duration.
      const th = 2 * Math.PI * (u + jerky * Math.sin(2 * Math.PI * 3 * u) / (2 * Math.PI * 3));
      const h = H * (1 - Math.cos(th)) / 2;
      point(x + c * th + w * Math.sin(th) + slant * h, base - h);
      t += dt;
    }
    x += 2 * Math.PI * c;
    if (liftEvery && (k + 1) % liftEvery === 0 && k < n - 1) {
      t += 0.35; // pen in the air
      strokeStarts.push(samples.length);
    }
  }
  for (let r = 0; r < rest; r += dt) { point(x, base); t += dt; }
  return { samples, strokeStarts };
}

// ---------- letter shapes, for testing what counts as a loop ----------
// each shape is a list of control points (x right, h up) in units of the
// letter's height, starting and ending on the baseline. a smooth curve runs
// through them. `loop: true` shapes should count as loops, the rest shouldn't.
export const SHAPES = {
  // a closed cursive l: up the right, over the top, down the left, crossing.
  closedL: { loop: true, pts: [[0, 0], [0.3, 0.35], [0.5, 0.75], [0.42, 1], [0.3, 0.8], [0.3, 0.4], [0.42, 0.05], [0.6, 0]] },
  // a narrow l: up on a slant to the stem, up the stem and straight back down it.
  narrowL: { loop: true, pts: [[0, 0], [0.22, 0.38], [0.38, 0.68], [0.41, 1], [0.4, 0.68], [0.41, 0.3], [0.45, 0.05], [0.62, 0]] },
  // down along the way it went up, a little behind it, never crossing.
  retrace: { loop: true, pts: [[0, 0], [0.25, 0.5], [0.45, 1], [0.32, 0.55], [0.2, 0.2], [0.3, 0.03], [0.55, 0]] },
  // an e: in low from the left, up and back over the top, down behind, crossing the way in.
  eLoop: { loop: true, pts: [[0, 0.25], [0.3, 0.45], [0.4, 0.8], [0.28, 1], [0.12, 0.85], [0.08, 0.45], [0.2, 0.05], [0.6, 0]] },
  // a tent with a small curl at its top.
  curl: { loop: false, pts: [[0, 0], [0.3, 0.55], [0.42, 0.88], [0.5, 1], [0.58, 0.95], [0.55, 0.88], [0.48, 0.92], [0.55, 0.6], [0.75, 0]] },
  // a tooth: up on a slant, straight down.
  tooth: { loop: false, pts: [[0, 0], [0.2, 0.45], [0.4, 1], [0.41, 0.5], [0.43, 0.08], [0.6, 0]] },
  // a spike: straight up and straight down, forward.
  spike: { loop: false, pts: [[0, 0], [0.32, 1], [0.6, 0]] },
  // a round hump.
  hump: { loop: false, pts: [[0, 0], [0.2, 0.75], [0.4, 1], [0.6, 0.75], [0.8, 0]] },
  // an n: up, across the top, down.
  nArch: { loop: false, pts: [[0, 0], [0.05, 0.9], [0.25, 1], [0.5, 0.9], [0.55, 0]] },
};

function catmull(pts, perSeg) {
  const P = [pts[0], ...pts, pts.at(-1)], out = [];
  for (let i = 1; i < P.length - 2; i++) {
    const [p0, p1, p2, p3] = [P[i - 1], P[i], P[i + 1], P[i + 2]];
    for (let s = 0; s < perSeg; s++) {
      const u = s / perSeg, u2 = u * u, u3 = u2 * u;
      // uniform Catmull-Rom interpolation through the control points.
      out.push([0, 1].map((k) => 0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * u + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2 +
        (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * u3)));
    }
  }
  out.push(pts.at(-1));
  return out;
}

// a row of letters on a baseline at y = baselineY. letters: list of shape
// names (or { shape, height, drop }). height in px; drop moves the letter's
// base below the baseline (px). slant leans every letter forward (x per unit
// height). speed in letter-heights per second; jitter in px; sampled at hz.
export function letterRow(letters, {
  height = 120, baselineY = 300, x0 = 30, slant = 0.2, speed = 3, jitter = 0.4, hz = 120, seed = 1, widthScale = 1,
} = {}) {
  const rand = rng(seed);
  const samples = [];
  let x = x0, t = 0;
  for (const spec of letters) {
    const { shape, height: H = height, drop = 0 } = typeof spec === "string" ? { shape: spec } : spec;
    const pts = SHAPES[shape].pts.map(([px, ph]) => [px * widthScale, ph]);
    const curve = catmull(pts, 24);
    for (let i = 0; i < curve.length; i++) {
      const [px, ph] = curve[i];
      if (i) {
        const [qx, qh] = curve[i - 1];
        t += Math.hypot(px - qx, ph - qh) / speed;
      }
      if (!samples.length || t - samples.at(-1).t >= 1 / hz) {
        samples.push({ t, x: x + (px + slant * ph) * H + (rand() - 0.5) * 2 * jitter, y: baselineY + drop - ph * H + (rand() - 0.5) * 2 * jitter });
      }
    }
    x += pts.at(-1)[0] * H;
  }
  return { samples, strokeStarts: [0] };
}

// the same writing as a mouse reports it: whole-pixel positions, a sample each
// time it moves a pixel. two strokes then often cross by sharing a pixel
// rather than passing through each other.
export function mouseLike({ samples, strokeStarts = [0] }) {
  const lifts = new Set(strokeStarts), out = [], starts = [];
  for (let i = 0; i < samples.length; i++) {
    const b = samples[i], lift = lifts.has(i), a = lift ? b : samples[i - 1];
    if (lift) starts.push(out.length);
    const n = Math.max(1, Math.ceil(Math.hypot(b.x - a.x, b.y - a.y)));
    for (let k = lift ? n : 1; k <= n; k++) {
      const p = { t: a.t + ((b.t - a.t) * k) / n, x: Math.round(a.x + ((b.x - a.x) * k) / n), y: Math.round(a.y + ((b.y - a.y) * k) / n) };
      const q = out.at(-1);
      if (lift || !q || q.x !== p.x || q.y !== p.y) out.push(p);
    }
  }
  return { samples: out, strokeStarts: starts };
}
