// Practice exercises - the level rule, each exercise's levels and the measures taken on every try
// Pure functions with no DOM. Node tests them (tools/train-check.mjs) and the iPad app runs them through JavaScriptCore

export const HITS_TO_LEVEL_UP = 3;
export const MISSES_TO_LEVEL_DOWN = 3;
// 3 hits at a level move up one level, 3 misses IN A ROW move down one

export const SLOWER_LIMIT = 0.15;
export const SHAKIER_LIMIT = 0.15;
// A try that reached its target is still a miss if its pace or smoothness dropped more than this against recent tries
export const RECENT_TRIES = 5;
// How many recent counted tries the pace and smoothness are compared with

export const EXERCISES = {
  "big-writing": { built: true, levels: [0.2, 0.24, 0.28, 0.32, 0.36, 0.4, 0.45, 0.5, 0.55, 0.6] },
  // Target height as a share of the writing area's height
  rhythm: { built: true, levels: [40, 45, 50, 55, 60, 66, 72, 80, 88, 96] },
  // Beats per minute
  "steady-tracing": { built: true, levels: [1, 0.85, 0.7, 0.55, 0.45, 0.35, 0.25, 0.15, 0.08, 0] },
  // How visible the guide is, 1 = fully
  "hand-skills": { built: true, levels: [96, 84, 72, 64, 56, 48, 42, 36, 32, 28] },
  // Each target's starting width in CSS px
};
// Each exercise's levels, easy to hard. An exercise with built: false shows in the Training tab but can't be opened

export const newLevelState = () => ({ level: 0, hits: 0, misses: 0, last: null });
// Starting state - level 0 is Level 1, last is the most recent level change

// Next level state after one judged try. A try that didn't count changes nothing
export function applyTry(state, { counted, hit }, levelCount) {
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

// Drops one level and resets the counts. Level 1 stays unchanged
export function tooHard(state) {
  if (state.level === 0) return state;
  return { level: state.level - 1, hits: 0, misses: 0, last: "down" };
}

const median = (xs) => {
  if (!xs.length) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  if (s.length % 2) return s[m];
  return (s[m - 1] + s[m]) / 2;
};
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

export const STILL_PX = 4;
// A pen within this many px of where a stroke starts or ends isn't moving yet

// Cuts the time the pen sat still at the start and end of a stroke
export function trimStill(stroke) {
  const dist = (p, q) => Math.hypot(p.x - q.x, p.y - q.y);
  let a = 0;
  let b = stroke.length - 1;
  while (a < b && dist(stroke[a + 1], stroke[0]) < STILL_PX) {
    a++;
  }
  while (b > a && dist(stroke[b - 1], stroke[stroke.length - 1]) < STILL_PX) {
    b--;
  }
  return stroke.slice(a, b + 1);
}

// Time the pen was down and moving, path length, and the number of speed peaks
// A speed peak is one speed-up and slow-down of the pen
export function motionMeasures(samples, strokeStarts = [0]) {
  const bounds = [...strokeStarts, samples.length];
  let penDown = 0;
  let length = 0;
  let peaks = 0;
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

// Resamples the stroke at 60 Hz, averages the speed over 5 samples and counts its peaks
function speedPeaks(stroke) {
  const t0 = stroke[0].t;
  const t1 = stroke[stroke.length - 1].t;
  const step = 1 / 60;
  const pts = [];
  let j = 0;
  for (let t = t0; t <= t1; t += step) {
    while (j < stroke.length - 2 && stroke[j + 1].t < t) {
      j++;
    }
    const a = stroke[j];
    const b = stroke[j + 1];
    let f = 0;
    if (b.t > a.t) {
      f = Math.min(1, Math.max(0, (t - a.t) / (b.t - a.t)));
    }
    pts.push([a.x + f * (b.x - a.x), a.y + f * (b.y - a.y)]);
  }
  if (pts.length < 5) return 0;
  const raw = [];
  for (let i = 1; i < pts.length; i++) {
    const dx = pts[i][0] - pts[i - 1][0];
    const dy = pts[i][1] - pts[i - 1][1];
    raw.push(Math.hypot(dx, dy) / step);
  }
  const speed = raw.map((_, i) => {
    const w = raw.slice(Math.max(0, i - 2), i + 3);
    return mean(w);
  });
  const delta = 0.25 * median(speed);
  // A peak only counts once the speed drops a quarter of the median speed below it
  if (!(delta > 0)) return 0;
  let count = 0;
  let rising = true;
  let best = -Infinity;
  let low = Infinity;
  for (const v of speed) {
    if (rising) {
      if (v > best) {
        best = v;
      } else if (v < best - delta) {
        count++;
        rising = false;
        low = v;
      }
    } else if (v < low) {
      low = v;
    } else if (v > low + delta) {
      rising = true;
      best = v;
    }
  }
  if (rising && best > low + delta) return count + 1;
  return count;
}

// ---------- big writing: tall loops ("llll") between a baseline and a target line ----------
export const REACH = 0.9;
// A loop touches the line when its top reaches this share of the target height
export const OWN_REACH = 0.85;
// The loop's height from its own bottom must also reach this share
export const HIT_SHARE = 0.75;
// Share of detected letters that must reach the line
export const MIN_LOOPS = 4;
// Minimum number of detected letters for a counted try
export const MIN_LOOP = 0.15;
// A rise smaller than this share of the target height is never a loop
export const MIN_STEP = 0.15;
// If a letter's top is less than this share of its height to the right of the last one, it's the last letter written over
export const CLOSE_DEPTH = 0.2;
// A letter is a loop if EITHER its down-stroke crosses or touches its up-stroke at least this share of its height below its top
export const TOUCH_PX = 1;
// Strokes within this many CSS px count as touching - mouse strokes often cross by sharing a pixel
export const BACK_LIMIT = 0.05;
const BACK_DEPTHS = [0.1, 0.2, 0.3];
// OR, near its top, its down-stroke runs no more than this share of its height right of its up-stroke,
// averaged at 10, 20 and 30% of its height below the top. Spikes, teeth, humps and n's come down further right
export const BELOW_LIMIT = 0.25;
// A letter's bottom can be at most this share of the target height below the drawn baseline

// Alternating peaks and troughs of h, each at least the drop distance from the one before
function turningPoints(h, drop) {
  const out = [];
  let mode = 0;
  // Mode 1 = rising, -1 = falling, 0 = not known yet
  let hi = 0;
  let lo = 0;
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
  if (mode === 1 && out.length && h[hi] - h[out.at(-1).i] >= drop) {
    out.push({ i: hi, peak: true });
  }
  if (mode === -1) {
    out.push({ i: lo, peak: false });
  }
  // Adds the last turn when the pen lifted at the top of the last loop or on the way down from it
  return out;
}

function segmentsCross(p1, p2, p3, p4) {
  const side = (a, b, c) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  const crossesLine34 = side(p3, p4, p1) * side(p3, p4, p2) < 0;
  const crossesLine12 = side(p1, p2, p3) * side(p1, p2, p4) < 0;
  // Each segment's ends are on opposite sides of the other one's line
  return crossesLine34 && crossesLine12;
}

// Shortest distance from point p to segment a-b
function toSegment(p, a, b) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  let f = 0;
  if (len2) {
    f = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
  }
  return Math.hypot(p.x - a.x - f * dx, p.y - a.y - f * dy);
}

// True when the segments cross or come within TOUCH_PX of each other
function segmentsMeet(p1, p2, p3, p4) {
  if (segmentsCross(p1, p2, p3, p4)) return true;
  const closest = Math.min(
    toSegment(p1, p3, p4),
    toSegment(p2, p3, p4),
    toSegment(p3, p1, p2),
    toSegment(p4, p1, p2),
  );
  return closest <= TOUCH_PX;
}

// True when the stroke coming down from the top crosses or touches the stroke going up to it, at least
// CLOSE_DEPTH of its height below the top. Segments across a pen lift are skipped
function closesAround(samples, h, lifts, from, top, to, own) {
  const deep = h[top] - CLOSE_DEPTH * own;
  // The strokes must meet at or below this height
  for (let i = from; i < top; i++) {
    if (lifts.has(i + 1)) continue;
    const ilo = Math.min(h[i], h[i + 1]);
    const ihi = Math.max(h[i], h[i + 1]);
    if (ilo > deep) continue;
    for (let j = top; j < to; j++) {
      if (lifts.has(j + 1)) continue;
      const jlo = Math.min(h[j], h[j + 1]);
      const jhi = Math.max(h[j], h[j + 1]);
      if (jlo > ihi + TOUCH_PX || ilo > jhi + TOUCH_PX) continue;
      // Too far apart in height to meet
      if ((h[i] + h[i + 1] + h[j] + h[j + 1]) / 4 > deep) continue;
      if (segmentsMeet(samples[i], samples[i + 1], samples[j], samples[j + 1])) return true;
    }
  }
  return false;
}

// Returns up and down - the x where the line crosses height level going up to the top and coming back down
// Interpolated between samples. null on a side that never gets that low
function sidesAt(samples, h, from, top, to, level) {
  const at = (a, b) => {
    let f = 0;
    if (h[b] !== h[a]) {
      f = (level - h[a]) / (h[b] - h[a]);
    }
    return samples[a].x + f * (samples[b].x - samples[a].x);
  };
  let d = top;
  while (d < to && h[d] > level) {
    d++;
  }
  let u = top;
  while (u > from && h[u] > level) {
    u--;
  }
  let up = null;
  if (h[u] <= level && u < top) {
    up = at(u, u + 1);
  }
  let down = null;
  if (h[d] <= level && d > top) {
    down = at(d - 1, d);
  }
  return { up, down };
}

// How far right of its up-stroke a letter's down-stroke runs near its top, as a share of its height,
// averaged over BACK_DEPTHS. Negative when it comes down to the left, null when a side never gets that low
function backSide(samples, h, from, top, to, own) {
  const gaps = [];
  for (const f of BACK_DEPTHS) {
    const { up, down } = sidesAt(samples, h, from, top, to, h[top] - f * own);
    if (up == null || down == null) return null;
    gaps.push((down - up) / own);
  }
  return mean(gaps);
}

// Every letter in a row of writing, loop or not - its top above the baseline, its height from its own bottom,
// its bottom, whether it's a loop and where its top is, in CSS px
export function findLoops(samples, baselineY, targetPx, strokeStarts = [0]) {
  if (samples.length < 2) return [];
  const h = samples.map((p) => baselineY - p.y);
  const drop = Math.max(6, MIN_LOOP * targetPx);
  const sorted = [...h].sort((p, q) => p - q);
  const base = sorted[Math.floor(0.1 * (sorted.length - 1))];
  // The writer's own baseline, the 10th percentile height
  const letters = [];
  let valley = null;
  // Lowest trough after the current letter's top
  for (const p of turningPoints(h, drop)) {
    if (!p.peak) {
      if (valley == null || h[p.i] < h[valley]) valley = p.i;
      continue;
    }
    const cur = letters.at(-1);
    if (cur && valley != null) {
      const lower = Math.min(h[cur.top], h[p.i]);
      const rise = lower - h[valley];
      const over = samples[p.i].x - samples[cur.top].x < MIN_STEP * rise;
      // Top not far enough right of the last letter - written over it
      if (over || rise < 0.5 * (lower - base)) {
        if (h[p.i] > h[cur.top]) cur.top = p.i;
        valley = null;
        continue;
      }
      // A dip less than halfway back down to the baseline, or a write-over, is the same letter
      cur.after = valley;
    }
    letters.push({ top: p.i, before: valley, after: null });
    valley = null;
  }
  if (letters.length) letters.at(-1).after = valley;

  const lifts = new Set(strokeStarts);
  return letters.map(({ top, before, after }) => {
    const from = before ?? 0;
    const to = after ?? samples.length - 1;
    const bottom = Math.min(h[from], h[to]);
    const own = h[top] - bottom;
    const closed = closesAround(samples, h, lifts, from, top, to, own);
    const back = backSide(samples, h, from, top, to, own);
    const loop = closed || (back != null && back <= BACK_LIMIT);
    return { i: top, top: h[top], own, bottom, closed, back, loop, x: samples[top].x, y: samples[top].y };
  }).filter((l) => l.own >= drop);
}

// A loop that reached the line from a base on the baseline
export function reachesLine(loop, targetPx) {
  const onBaseline = loop.bottom >= -BELOW_LIMIT * targetPx;
  const tallEnough = loop.top >= REACH * targetPx && loop.own >= OWN_REACH * targetPx;
  return loop.loop && onBaseline && tallEnough;
}

// Pace and smoothness against the median of recent counted tries, as fractions (+0.1 = 10% more)
// Each is null when there's nothing to compare. peaksKey names the exercise's smoothness measure, lower = smoother
export function compareRecent(measures, recent, peaksKey = "peaksPerLoop") {
  const prev = recent.slice(0, RECENT_TRIES);
  if (!prev.length) return { pace: null, smoothness: null };
  const known = (key) => prev.map((m) => m[key]).filter(Number.isFinite);
  // Leaves out tries saved before a measure existed
  const pace = median(known("pace"));
  const peaks = median(known(peaksKey));
  return {
    pace: pace > 0 ? measures.pace / pace - 1 : null,
    smoothness: peaks > 0 ? 1 - measures[peaksKey] / peaks : null,
    // Lower values count as smoother
  };
}

// The hit rule for the exercises - a try that reached its target is still a miss if it got slower or shakier
function judge(counted, reachedTarget, vs, measures, extra = {}, shakierLimit = SHAKIER_LIMIT) {
  const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
  const shakier = vs.smoothness != null && vs.smoothness < -shakierLimit;
  const hit = reachedTarget && !slower && !shakier;
  return { counted, reachedTarget, slower, shakier, hit, measures, vs, ...extra };
}

// Scores one big-writing try. recent holds the measures of recent counted tries, newest first
export function scoreBigWriting(samples, strokeStarts, { baselineY, targetPx }, recent = []) {
  const found = findLoops(samples, baselineY, targetPx, strokeStarts);
  const tops = found.map((l) => l.own);
  const motion = motionMeasures(samples, strokeStarts);
  const loops = found.length;
  const reached = found.filter((l) => reachesLine(l, targetPx)).length;
  const third = Math.floor(loops / 3);
  let shrink = NaN;
  if (third >= 2) {
    shrink = mean(tops.slice(-third)) / mean(tops.slice(0, third)) - 1;
  }
  // Last third of the row against the first third, negative when it shrank
  const measures = {
    loops,
    reached,
    open: found.filter((l) => !l.loop).length,
    // Letters shaped like a spike, hump or arch
    below: found.filter((l) => l.loop && l.bottom < -BELOW_LIMIT * targetPx).length,
    // Loops whose base dipped well below the baseline
    size: loops ? median(tops) / targetPx : NaN,
    // Median letter height relative to the target height
    accuracy: loops ? reached / loops : NaN,
    // Share of detected letters that reached the line
    shrink,
    pace: motion.penDown > 0 ? loops / motion.penDown : NaN,
    peaksPerLoop: loops ? motion.peaks / loops : NaN,
  };
  const counted = loops >= MIN_LOOPS && measures.pace > 0;
  const vs = counted ? compareRecent(measures, recent) : { pace: null, smoothness: null };
  const reachedTarget = counted && measures.accuracy >= HIT_SHARE;
  const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
  const shakier = vs.smoothness != null && vs.smoothness < -SHAKIER_LIMIT;
  const marks = found.map((l) => ({ x: l.x, y: l.y, reached: reachesLine(l, targetPx) }));
  // Where each loop topped out, for the marks on the writing. Not saved
  const hit = reachedTarget && !slower && !shakier;
  return { counted, reachedTarget, slower, shakier, hit, measures, vs, marks };
}

// ---------- paths to follow (steady tracing, rhythm) ----------
// A path's points plus the distance along it to each one, in CSS px
export function makePath(points) {
  const x = points.map((p) => p[0]);
  const y = points.map((p) => p[1]);
  const s = [0];
  for (let i = 1; i < points.length; i++) {
    s.push(s[i - 1] + Math.hypot(x[i] - x[i - 1], y[i] - y[i - 1]));
  }
  return { x, y, s, length: s[s.length - 1] };
}

// Closest point on the path to px, py - how far away it is and how far along the path
export function nearestOnPath(path, px, py) {
  let dist = Infinity;
  let along = 0;
  for (let i = 1; i < path.x.length; i++) {
    const ax = path.x[i - 1];
    const ay = path.y[i - 1];
    const dx = path.x[i] - ax;
    const dy = path.y[i] - ay;
    const len2 = dx * dx + dy * dy;
    let f = 0;
    if (len2) {
      f = Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / len2));
    }
    const d = Math.hypot(px - ax - f * dx, py - ay - f * dy);
    if (d < dist) {
      dist = d;
      along = path.s[i - 1] + f * Math.sqrt(len2);
    }
  }
  return { dist, along };
}

export function pointAlong(path, along) {
  const a = Math.min(Math.max(along, 0), path.length);
  let i = 1;
  while (i < path.s.length - 1 && path.s[i] < a) {
    i++;
  }
  const span = path.s[i] - path.s[i - 1];
  let f = 0;
  if (span) {
    f = (a - path.s[i - 1]) / span;
  }
  const x = path.x[i - 1] + f * (path.x[i] - path.x[i - 1]);
  const y = path.y[i - 1] + f * (path.y[i] - path.y[i - 1]);
  return [x, y];
}

export const COVER_PIECES = 40;
// The path is cut into this many equal pieces. A piece counts as traced when the pen passed close to it
function coverage(nearest, length, closePx) {
  const done = new Set();
  for (const n of nearest) {
    if (n.dist <= closePx) {
      const piece = Math.floor((n.along / length) * COVER_PIECES);
      done.add(Math.min(COVER_PIECES - 1, piece));
    }
  }
  return done.size / COVER_PIECES;
}

// ---------- steady tracing: trace a spiral while its guide fades ----------
export const TRACE_TURNS = 3;
export const TRACE_COVER = 0.9;
// A hit traces at least this share of the spiral
export const TRACE_LIMIT = 0.05;
// A hit stays this close to the spiral on average, as a share of its radius
export const TRACE_MIN_COVER = 0.5;
// Less than this share traced and the try doesn't count

// The spiral, centered in a w x h area, starting from the middle
export function tracingPath(w, h) {
  const radius = Math.min(w, h) / 2 - 24;
  const n = 600;
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const p = i / n;
    const th = p * TRACE_TURNS * 2 * Math.PI;
    pts.push([w / 2 + p * radius * Math.cos(th), h / 2 + p * radius * Math.sin(th)]);
  }
  return { ...makePath(pts), radius };
}

export function scoreTracing(samples, strokeStarts, path, recent = []) {
  const nearest = samples.map((p) => nearestOnPath(path, p.x, p.y));
  const cover = coverage(nearest, path.length, 0.12 * path.radius);
  const distPx = nearest.length ? mean(nearest.map((n) => n.dist)) : NaN;
  const motion = motionMeasures(samples, strokeStarts);
  const turns = TRACE_TURNS * cover;
  const measures = {
    cover,
    distPx,
    accuracy: distPx / path.radius,
    // Average distance from the guide as a share of the spiral's radius
    pace: motion.penDown > 0 ? (cover * path.length) / path.radius / motion.penDown : NaN,
    // Spiral radii traced per second, the same on any canvas size
    peaksPerTurn: turns > 0 ? motion.peaks / turns : NaN,
  };
  const counted = cover >= TRACE_MIN_COVER && measures.pace > 0;
  const vs = counted ? compareRecent(measures, recent, "peaksPerTurn") : { pace: null, smoothness: null };
  const reached = counted && cover >= TRACE_COVER && measures.accuracy <= TRACE_LIMIT;
  return judge(counted, reached, vs, measures, { limitPx: TRACE_LIMIT * path.radius });
}

// ---------- rhythm: trace a wave in time with a dot moving to a metronome ----------
export const RHYTHM_BEATS = 8;
export const COUNT_IN = 3;
// Lead-in beats before the dot sets off
export const RHYTHM_COVER = 0.85;
// A hit traces at least this share of the wave
export const RHYTHM_LAG = 0.5;
// A hit stays within this many beats of the dot on average
export const RHYTHM_NEAR = 0.25;
// A hit stays this close to the wave on average, as a share of its height
export const RHYTHM_MIN_COVER = 0.4;
// Less than this share traced and the try doesn't count

// The wave across a w x h area, starting bottom left. Beat k ends at along = k * beatLength, on a top or a bottom
export function rhythmPath(w, h) {
  const left = 0.08 * w;
  const right = 0.92 * w;
  const mid = h / 2;
  const amp = 0.3 * h;
  const n = 60 * RHYTHM_BEATS;
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const p = i / n;
    pts.push([left + p * (right - left), mid + amp * Math.cos(Math.PI * p * RHYTHM_BEATS)]);
  }
  const path = makePath(pts);
  return { ...path, height: 2 * amp, beatLength: path.length / RHYTHM_BEATS };
}

export const WOBBLE_SECS = 0.25;
// Rhythm's smoothness is side-to-side wobble, not speed peaks - how far the pen strays across the wave and back
// within this many seconds, RMS in CSS px, while the dot is moving
export const RHYTHM_SHAKIER_LIMIT = 0.5;
// Wobble more than 50% above the recent median counts as shakier

function wobble(samples, strokeStarts, path, nearest, moving) {
  const side = samples.map((p, i) => {
    const a = pointAlong(path, nearest[i].along - 1);
    const b = pointAlong(path, nearest[i].along + 1);
    const cross = (b[0] - a[0]) * (p.y - a[1]) - (b[1] - a[1]) * (p.x - a[0]);
    return Math.sign(cross) * nearest[i].dist;
  });
  // Signed distance from the wave, positive on one side and negative on the other
  const bounds = [...strokeStarts, samples.length];
  const half = Math.round((WOBBLE_SECS * 60) / 2);
  let sum = 0;
  let count = 0;
  for (let k = 0; k < bounds.length - 1; k++) {
    const a = bounds[k];
    const b = bounds[k + 1];
    if (b - a < 2) continue;
    const r = [];
    const ts = [];
    let j = a;
    for (let t = samples[a].t; t <= samples[b - 1].t; t += 1 / 60) {
      while (j < b - 2 && samples[j + 1].t < t) {
        j++;
      }
      const p = samples[j];
      const q = samples[j + 1];
      let f = 0;
      if (q.t > p.t) {
        f = Math.min(1, Math.max(0, (t - p.t) / (q.t - p.t)));
      }
      r.push(side[j] + f * (side[j + 1] - side[j]));
      ts.push(t);
    }
    // The side distance resampled at 60 Hz
    for (let i = 0; i < r.length; i++) {
      if (!moving(ts[i])) continue;
      const around = mean(r.slice(Math.max(0, i - half), i + half + 1));
      sum += (r[i] - around) ** 2;
      count++;
    }
    // RMS of the side distance around its moving average, only while the dot moves
  }
  return count ? Math.sqrt(sum / count) : NaN;
}

// Timing is { beatSec, penOffset } - penOffset is seconds from the dot setting off to the pen's first sample,
// negative when the pen was down first
export function scoreRhythm(samples, strokeStarts, path, { beatSec, penOffset }, recent = []) {
  const nearest = samples.map((p) => nearestOnPath(path, p.x, p.y));
  const end = RHYTHM_BEATS * beatSec;
  const lags = [];
  samples.forEach((p, i) => {
    const t = p.t + penOffset;
    // Seconds after the dot set off
    if (t < 0 || t > end) return;
    lags.push(nearest[i].along / path.beatLength - t / beatSec);
    // Beats ahead of the dot, negative when behind it
  });
  const cover = coverage(nearest, path.length, 0.2 * path.height);
  const motion = motionMeasures(samples, strokeStarts);
  const beats = RHYTHM_BEATS * cover;
  const moving = (t) => t + penOffset >= 0 && t + penOffset <= end;
  const measures = {
    cover,
    lag: lags.length ? mean(lags.map(Math.abs)) : NaN,
    // Beats from the dot, ignoring ahead or behind
    lead: lags.length ? mean(lags) : NaN,
    // The same with its sign
    near: nearest.length ? mean(nearest.map((n) => n.dist)) / path.height : NaN,
    peaksPerBeat: beats > 0 ? motion.peaks / beats : NaN,
    wobble: wobble(samples, strokeStarts, path, nearest, moving),
    // Side-to-side wobble while the dot moved, in CSS px
  };
  const counted = cover >= RHYTHM_MIN_COVER && lags.length >= 10;
  let smoothness = null;
  if (counted) {
    smoothness = compareRecent(measures, recent, "wobble").smoothness;
  }
  const vs = { pace: null, smoothness };
  // Only smoothness is compared with recent tries - the metronome sets the pace
  const reached = counted && cover >= RHYTHM_COVER && measures.lag <= RHYTHM_LAG && measures.near <= RHYTHM_NEAR;
  return judge(counted, reached, vs, measures, {}, RHYTHM_SHAKIER_LIMIT);
}

// ---------- hand skills: tap each shrinking target before it's gone ----------
export const TARGETS = 15;
export const SHRINK_SECS = 2;
// Seconds for a target to shrink from its starting size to nothing
export const CATCH_SHARE = 0.8;
// A hit catches at least this share of the targets
export const TAP_PRECISION = 0.8;
// A hit needs at least this share of all taps on a target

export const targetRadius = (startSize, secs) => Math.max(0, (startSize / 2) * (1 - secs / SHRINK_SECS));
// A target's radius secs seconds after it appeared, 0 once it's gone

// Each result is { caught, ms } for one target, ms from appearing to the catching tap. extraTaps counts the taps that missed every target
export function scoreTargets(results, extraTaps) {
  const caught = results.filter((r) => r.caught);
  const taps = caught.length + extraTaps;
  const measures = {
    targets: results.length,
    caught: caught.length,
    extraTaps,
    reactionMs: caught.length ? median(caught.map((r) => r.ms)) : NaN,
    precision: taps ? caught.length / taps : 0,
    // Share of all taps that caught a target
  };
  const counted = results.length >= TARGETS;
  const reached = counted && caught.length / results.length >= CATCH_SHARE && measures.precision >= TAP_PRECISION;
  return judge(counted, reached, { pace: null, smoothness: null }, measures);
  // Nothing is compared with recent tries - the clock sets the pace
}
