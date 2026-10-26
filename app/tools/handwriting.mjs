// HANDWRITING.MJS MAKES FAKE HANDWRITING FOR TESTING TRAIN.JS
// IT MAKES ROWS OF CURSIVE L'S AND ROWS OF TEST LETTER SHAPES, WITH A SMALL RANDOM WOBBLE
// THE WOBBLE COMES FROM A FIXED SEED, SO EVERY RUN MAKES THE SAME POINTS


// Make repeatable random numbers from a seed, using Mulberry32
// Adapted from stackoverflow.com/a/47593316/1036426
function rng(seed) {
  let a = seed >>> 0;

  // Each call gives the next random number from 0 to 1
  function next() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  return next;
}


// Make a row of cursive l's
// slant is how far right each point moves per pixel of height
// sizeVar is how much each loop's size changes at random, 0.1 means up to 10% bigger or smaller
// shrinkBy is how much smaller the last loop is than the first
// liftEvery lifts the pen every that many loops
// floatPx moves the whole row that many pixels above the baseline
// rest is the seconds of still pen before and after the row
// jerky is how much the speed swings inside each loop, from 0 to 1
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

  // Add one point with a small random wobble
  function point(px, py) {
    const jx = (rand() - 0.5) * 2 * jitter;
    const jy = (rand() - 0.5) * 2 * jitter;
    samples.push({ t, x: px + jx, y: py + jy });
  }

  // The row sits floatPx above the baseline
  const base = baselineY - floatPx;

  // Hold the pen still before the row
  for (let r = 0; r < rest; r += dt) {
    point(x, base);
    t += dt;
  }

  for (let k = 0; k < n; k++) {

    // Find this loop's height, shrinking along the row and changing a little at random
    const shrink = 1 - shrinkBy * (k / Math.max(1, n - 1));
    const vary = 1 + (rand() - 0.5) * 2 * sizeVar;
    const H = height * shrink * vary;

    // Find how far the loop moves right and how wide it is
    const c = (0.45 * H) / (2 * Math.PI);
    const w = 1.7 * c;
    const steps = Math.round(loopSecs * hz);

    for (let s = 0; s < steps; s++) {
      const u = s / steps;

      // Change the speed inside the loop without changing how long the loop takes
      const warp = jerky * Math.sin(2 * Math.PI * 3 * u) / (2 * Math.PI * 3);
      const th = 2 * Math.PI * (u + warp);

      // Go up and back down once per loop, moving right and slanting
      const h = H * (1 - Math.cos(th)) / 2;
      point(x + c * th + w * Math.sin(th) + slant * h, base - h);
      t += dt;
    }

    // Move to where the next loop starts
    x += 2 * Math.PI * c;

    // Lift the pen every liftEvery loops, but not after the last loop
    if (liftEvery && (k + 1) % liftEvery === 0 && k < n - 1) {
      t += 0.35;
      strokeStarts.push(samples.length);
    }
  }

  // Hold the pen still after the row
  for (let r = 0; r < rest; r += dt) {
    point(x, base);
    t += dt;
  }

  return { samples, strokeStarts };
}


// LETTER SHAPES FOR TESTING WHAT COUNTS AS A LOOP
// Each shape is a list of points in letter heights, with x going right and h going up
// Shapes with loop true must count as loops, and the rest must not
export const SHAPES = {

  // A closed cursive l, up the right, over the top, down the left, crossing
  closedL: { loop: true, pts: [[0, 0], [0.3, 0.35], [0.5, 0.75], [0.42, 1], [0.3, 0.8], [0.3, 0.4], [0.42, 0.05], [0.6, 0]] },

  // A narrow l, up on a slant to the stem, then up the stem and straight back down it
  narrowL: { loop: true, pts: [[0, 0], [0.22, 0.38], [0.38, 0.68], [0.41, 1], [0.4, 0.68], [0.41, 0.3], [0.45, 0.05], [0.62, 0]] },

  // An l written back down along its up stroke, a little behind it, never crossing
  retrace: { loop: true, pts: [[0, 0], [0.25, 0.5], [0.45, 1], [0.32, 0.55], [0.2, 0.2], [0.3, 0.03], [0.55, 0]] },

  // An e, in low from the left, up and back over the top, then down behind, crossing the way in
  eLoop: { loop: true, pts: [[0, 0.25], [0.3, 0.45], [0.4, 0.8], [0.28, 1], [0.12, 0.85], [0.08, 0.45], [0.2, 0.05], [0.6, 0]] },

  // A tent with a small curl at its top
  curl: { loop: false, pts: [[0, 0], [0.3, 0.55], [0.42, 0.88], [0.5, 1], [0.58, 0.95], [0.55, 0.88], [0.48, 0.92], [0.55, 0.6], [0.75, 0]] },

  // A tooth, up on a slant and straight down
  tooth: { loop: false, pts: [[0, 0], [0.2, 0.45], [0.4, 1], [0.41, 0.5], [0.43, 0.08], [0.6, 0]] },

  // A spike, straight up and straight down, moving forward
  spike: { loop: false, pts: [[0, 0], [0.32, 1], [0.6, 0]] },

  // A round hump
  hump: { loop: false, pts: [[0, 0], [0.2, 0.75], [0.4, 1], [0.6, 0.75], [0.8, 0]] },

  // An n, up, across the top and down
  nArch: { loop: false, pts: [[0, 0], [0.05, 0.9], [0.25, 1], [0.5, 0.9], [0.55, 0]] },
};


// Draw a smooth Catmull Rom curve through the points, with perSeg points between each pair
function catmull(pts, perSeg) {

  // Repeat the first and last point so the curve starts and ends on them
  const P = [pts[0], ...pts, pts.at(-1)];
  const out = [];

  for (let i = 1; i < P.length - 2; i++) {

    // The four points around this part of the curve
    const p0 = P[i - 1];
    const p1 = P[i];
    const p2 = P[i + 1];
    const p3 = P[i + 2];

    for (let s = 0; s < perSeg; s++) {
      const u = s / perSeg;
      const u2 = u * u;
      const u3 = u2 * u;

      // Find the x and then the h of the curve at u
      const point = [];
      for (let k = 0; k < 2; k++) {
        const a = 2 * p1[k];
        const b = (-p0[k] + p2[k]) * u;
        const c = (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2;
        const d = (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * u3;
        point.push(0.5 * (a + b + c + d));
      }
      out.push(point);
    }
  }

  // End on the last point
  out.push(pts.at(-1));
  return out;
}


// Make a row of SHAPES letters on the baseline
// letters holds shape names, or objects with a shape, a height and a drop
// drop moves a letter's bottom that many pixels below the baseline
// speed is in letter heights per second
export function letterRow(letters, {
  height = 120, baselineY = 300, x0 = 30, slant = 0.2, speed = 3, jitter = 0.4, hz = 120, seed = 1, widthScale = 1,
} = {}) {
  const rand = rng(seed);
  const samples = [];
  let x = x0;
  let t = 0;

  for (const spec of letters) {

    // A shape name on its own becomes an object with just the shape
    let opts = spec;
    if (typeof spec === "string") {
      opts = { shape: spec };
    }
    const { shape, height: H = height, drop = 0 } = opts;

    // Stretch the shape's points sideways by widthScale, then draw a smooth curve through them
    const pts = [];
    for (const [px, ph] of SHAPES[shape].pts) {
      pts.push([px * widthScale, ph]);
    }
    const curve = catmull(pts, 24);

    for (let i = 0; i < curve.length; i++) {
      const [px, ph] = curve[i];

      // Move the time forward by how long the pen takes to get from the last point to this one
      if (i) {
        const [qx, qh] = curve[i - 1];
        t += Math.hypot(px - qx, ph - qh) / speed;
      }

      // Add a point only once enough time has passed since the last one, with a small random wobble
      if (!samples.length || t - samples.at(-1).t >= 1 / hz) {
        const jx = (rand() - 0.5) * 2 * jitter;
        const jy = (rand() - 0.5) * 2 * jitter;
        samples.push({ t, x: x + (px + slant * ph) * H + jx, y: baselineY + drop - ph * H + jy });
      }
    }

    // Move to where the next letter starts
    x += pts.at(-1)[0] * H;
  }

  return { samples, strokeStarts: [0] };
}


// Turn writing into what a mouse would record, with whole pixel positions and one point per pixel moved
export function mouseLike({ samples, strokeStarts = [0] }) {
  const lifts = new Set(strokeStarts);
  const out = [];
  const starts = [];

  for (let i = 0; i < samples.length; i++) {
    const b = samples[i];
    const lift = lifts.has(i);

    // Fill in from the last point to this one, or start fresh at a pen lift
    let a = samples[i - 1];
    if (lift) {
      a = b;
      starts.push(out.length);
    }

    // Count the pixels between the two points
    const n = Math.max(1, Math.ceil(Math.hypot(b.x - a.x, b.y - a.y)));

    // At a pen lift only add the point itself, otherwise add one point per pixel
    let first = 1;
    if (lift) {
      first = n;
    }

    for (let k = first; k <= n; k++) {

      // Find the point k pixels along, rounded to whole pixels
      const p = {
        t: a.t + ((b.t - a.t) * k) / n,
        x: Math.round(a.x + ((b.x - a.x) * k) / n),
        y: Math.round(a.y + ((b.y - a.y) * k) / n),
      };

      // Keep it only if it moved to a new pixel, or it starts a stroke
      const q = out.at(-1);
      const moved = !q || q.x !== p.x || q.y !== p.y;
      if (lift || moved) {
        out.push(p);
      }
    }
  }

  return { samples: out, strokeStarts: starts };
}