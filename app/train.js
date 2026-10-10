// training: exercise levels, the level rule and what gets measured on every
// try. pure functions, no DOM - so node can test it (tools/train-check.mjs)
// and the Swift app can run it through JavaScriptCore like nt-features.js.

// the level rule (agreed Oct 2): hit the target 3 times at a level to move up,
// miss 3 times in a row to move back one, and "too hard today" drops one level
// whenever the person asks.
export const HITS_TO_LEVEL_UP = 3;
export const MISSES_TO_LEVEL_DOWN = 3;

// a try that reached its target still isn't a hit if the pace dropped or the
// movement got less smooth by more than this, compared with recent tries.
// writing bigger by slowing down is the trade-off amplitude training is known
// for (Markdowns/NeuroTrace_RealWorldGaps.md, gap 1).
export const SLOWER_LIMIT = 0.15;
export const SHAKIER_LIMIT = 0.15;
// how many recent counted tries the pace and smoothness are compared with.
export const RECENT_TRIES = 5;

// each exercise's levels, easy to hard. exercises with built: false show in
// the Training tab but can't be opened yet.
export const EXERCISES = {
  // target height as a share of the writing area's height.
  "big-writing": { built: true, levels: [0.2, 0.24, 0.28, 0.32, 0.36, 0.4, 0.45, 0.5, 0.55, 0.6] },
  // beats per minute.
  rhythm: { built: true, levels: [40, 45, 50, 55, 60, 66, 72, 80, 88, 96] },
  // how visible the guide is, 1 = fully.
  "steady-tracing": { built: true, levels: [1, 0.85, 0.7, 0.55, 0.45, 0.35, 0.25, 0.15, 0.08, 0] },
  // each target's starting width in CSS px.
  "hand-skills": { built: true, levels: [96, 84, 72, 64, 56, 48, 42, 36, 32, 28] },
};

// level is an index into the exercise's levels (0 = Level 1). hits count at
// this level, misses only in a row. last is the most recent level change.
export const newLevelState = () => ({ level: 0, hits: 0, misses: 0, last: null });

// a judged try -> the next level state. a try that didn't count (too short to
// judge) changes nothing.
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

// "too hard today": one level down straight away, no penalty. Level 1 stays.
export function tooHard(state) {
  if (state.level === 0) return state;
  return { level: state.level - 1, hits: 0, misses: 0, last: "down" };
}

const median = (xs) => {
  if (!xs.length) return NaN;
  const s = [...xs].sort((a, b) => a - b), m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

// a pen resting this close to where a stroke starts or ends isn't moving yet.
export const STILL_PX = 4;

// each stroke without the time the pen sat still at its start and end -
// resting the Pencil before writing isn't slow writing.
export function trimStill(stroke) {
  const dist = (p, q) => Math.hypot(p.x - q.x, p.y - q.y);
  let a = 0, b = stroke.length - 1;
  while (a < b && dist(stroke[a + 1], stroke[0]) < STILL_PX) a++;
  while (b > a && dist(stroke[b - 1], stroke[stroke.length - 1]) < STILL_PX) b--;
  return stroke.slice(a, b + 1);
}

// time the pen was down and moving, path length, and the number of speed
// peaks: each time the pen speeds up and slows down again. smooth writing has
// about two per loop (up and down); hesitant or shaky writing has more. speed
// is taken at 60 Hz within each stroke and lightly smoothed to reduce small jitter.
export function motionMeasures(samples, strokeStarts = [0]) {
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
    return mean(w);
  });
  // hysteresis: a peak only counts once speed has dropped by a quarter of the
  // stroke's typical speed below it.
  const delta = 0.25 * median(speed);
  if (!(delta > 0)) return 0;
  let count = 0, rising = true, best = -Infinity, low = Infinity;
  for (const v of speed) {
    if (rising) {
      if (v > best) best = v;
      else if (v < best - delta) { count++; rising = false; low = v; }
    } else if (v < low) low = v;
    else if (v > low + delta) { rising = true; best = v; }
  }
  return rising && best > low + delta ? count + 1 : count;
}

// ---------- big writing ----------
// a row of tall loops ("llll") between a baseline and a target line. a loop
// touches the line when its top reaches this share of the target height...
export const REACH = 0.9;
// ...and the loop itself, from its own bottom, is at least this tall - so
// small loops written up near the line don't count.
export const OWN_REACH = 0.75;
// share of loops that must touch the line for the try to reach its target.
export const HIT_SHARE = 0.75;
// fewer loops than this and the try is too short to judge.
export const MIN_LOOPS = 4;
// a rise smaller than this share of the target height is never a loop.
export const MIN_LOOP = 0.15;
// a letter whose top isn't at least this share of its height to the right of
// the one before is that letter written over again, not a new one.
export const MIN_STEP = 0.15;
// what makes a letter a loop rather than a spike, hump or arch - either:
// its down-stroke crosses or touches its up-stroke at least this share of its
// height below its top (a closed l, or a narrow one written back down over
// itself)...
export const CLOSE_DEPTH = 0.2;
// ...counting strokes this close (CSS px) as touching. a mouse moves in whole
// pixels, so two strokes often cross by sharing a pixel rather than passing
// through each other.
export const TOUCH_PX = 1;
// ...or, near its top, its down-stroke comes down behind its up-stroke or
// along it: at 10, 20 and 30% of its height below the top, the down-stroke is
// on average no more than this share of its height ahead of (right of) the
// up-stroke. a spike, tooth, hump or n comes down ahead of it.
export const BACK_LIMIT = 0.05;
const BACK_DEPTHS = [0.1, 0.2, 0.3];
// a letter stands on the baseline: its bottom no more than this share of the
// target height below the drawn baseline.
export const BELOW_LIMIT = 0.25;

// alternating peaks and troughs of h, each at least `drop` away from the one
// before (hysteresis), so jitter inside a stroke isn't a turning point.
function turningPoints(h, drop) {
  const out = [];
  let mode = 0, hi = 0, lo = 0; // mode 1 = rising, -1 = falling, 0 = not yet known
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
  // the pen lifted at the top of the last loop, or on the way down from it.
  if (mode === 1 && out.length && h[hi] - h[out.at(-1).i] >= drop) out.push({ i: hi, peak: true });
  if (mode === -1) out.push({ i: lo, peak: false });
  return out;
}

// do segments p1-p2 and p3-p4 cross?
function segmentsCross(p1, p2, p3, p4) {
  const side = (a, b, c) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  return side(p3, p4, p1) * side(p3, p4, p2) < 0 && side(p1, p2, p3) * side(p1, p2, p4) < 0;
}

// shortest distance from point p to segment a-b.
function toSegment(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy;
  const f = len2 ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0;
  return Math.hypot(p.x - a.x - f * dx, p.y - a.y - f * dy);
}

// do segments p1-p2 and p3-p4 cross, or come within TOUCH_PX of each other?
function segmentsMeet(p1, p2, p3, p4) {
  return segmentsCross(p1, p2, p3, p4) ||
    Math.min(toSegment(p1, p3, p4), toSegment(p2, p3, p4), toSegment(p3, p1, p2), toSegment(p4, p1, p2)) <= TOUCH_PX;
}

// does the stretch coming down from this top cross or touch the stretch going
// up to it, well below the top? that's what makes it a loop rather than a
// spike. no segment spans a pen lift.
function closesAround(samples, h, lifts, from, top, to, own) {
  const deep = h[top] - CLOSE_DEPTH * own; // they must meet at or below this height
  for (let i = from; i < top; i++) {
    if (lifts.has(i + 1)) continue;
    const ilo = Math.min(h[i], h[i + 1]), ihi = Math.max(h[i], h[i + 1]);
    if (ilo > deep) continue;
    for (let j = top; j < to; j++) {
      if (lifts.has(j + 1)) continue;
      const jlo = Math.min(h[j], h[j + 1]), jhi = Math.max(h[j], h[j + 1]);
      if (jlo > ihi + TOUCH_PX || ilo > jhi + TOUCH_PX) continue; // too far apart in height to meet
      if ((h[i] + h[i + 1] + h[j] + h[j + 1]) / 4 > deep) continue;
      if (segmentsMeet(samples[i], samples[i + 1], samples[j], samples[j + 1])) return true;
    }
  }
  return false;
}

// where the line passes height `level` on its way up to the top (up) and on
// its way down from it (down), interpolated between samples. null on a side
// that never gets that low.
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

// how far ahead of (right of) its up-stroke a letter's down-stroke runs near
// its top, as a share of its height: the mean over BACK_DEPTHS. negative when
// it comes down behind. null when a side never gets that low.
function backSide(samples, h, from, top, to, own) {
  const gaps = [];
  for (const f of BACK_DEPTHS) {
    const { up, down } = sidesAt(samples, h, from, top, to, h[top] - f * own);
    if (up == null || down == null) return null;
    gaps.push((down - up) / own);
  }
  return mean(gaps);
}

// every letter in a row of writing, small or tall, loop or not - each one
// is an attempt. for each: its top's height above the drawn baseline (top),
// its height above its own bottom (own), its bottom (bottom, below the
// baseline when negative), whether it's shaped like a loop (loop) and where
// its top is (x, y), all in CSS px. closed and back are the shape tests
// (see CLOSE_DEPTH, BACK_LIMIT), kept for tuning. a rise only starts a
// new letter if the line dipped at least halfway back down to the writer's
// baseline since the last one; a smaller dip is a wobble inside the same letter.
// a rise that doesn't move on to the right (MIN_STEP) is the same letter too.
export function findLoops(samples, baselineY, targetPx, strokeStarts = [0]) {
  if (samples.length < 2) return [];
  const h = samples.map((p) => baselineY - p.y);
  const drop = Math.max(6, MIN_LOOP * targetPx);
  const sorted = [...h].sort((p, q) => p - q);
  const base = sorted[Math.floor(0.1 * (sorted.length - 1))]; // the writer's own baseline
  const letters = [];
  let valley = null; // the lowest trough since the current letter's top
  for (const p of turningPoints(h, drop)) {
    if (!p.peak) {
      if (valley == null || h[p.i] < h[valley]) valley = p.i;
      continue;
    }
    const cur = letters.at(-1);
    if (cur && valley != null) {
      const lower = Math.min(h[cur.top], h[p.i]);
      const over = samples[p.i].x - samples[cur.top].x < MIN_STEP * (lower - h[valley]); // written over the last one
      if (over || lower - h[valley] < 0.5 * (lower - base)) {
        if (h[p.i] > h[cur.top]) cur.top = p.i; // a wobble or a write-over: same letter
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
    const loop = closed || (back != null && back <= BACK_LIMIT);
    return { i: top, top: h[top], own, bottom, closed, back, loop, x: samples[top].x, y: samples[top].y };
  }).filter((l) => l.own >= drop);
}

// a loop that reached the line, from a base on the baseline.
export const reachesLine = (loop, targetPx) =>
  loop.loop && loop.bottom >= -BELOW_LIMIT * targetPx && loop.top >= REACH * targetPx && loop.own >= OWN_REACH * targetPx;

// pace and smoothness against the median of recent counted tries, as
// fractions (+0.1 = 10% more). null when there's nothing to compare with yet.
// pace is loops a second: healthy writing keeps about the same rhythm at any
// size, so a pace that drops as the loops grow is the trade-off to catch.
// peaksKey names the exercise's smoothness measure, lower = smoother: speed
// peaks per loop or per turn, or rhythm's wobble.
export function compareRecent(measures, recent, peaksKey = "peaksPerLoop") {
  const prev = recent.slice(0, RECENT_TRIES);
  if (!prev.length) return { pace: null, smoothness: null };
  // tries saved before a measure existed don't have it; leave them out.
  const known = (key) => prev.map((m) => m[key]).filter(Number.isFinite);
  const pace = median(known("pace"));
  const peaks = median(known(peaksKey));
  return {
    pace: pace > 0 ? measures.pace / pace - 1 : null,
    // lower = smoother, so the sign is flipped.
    smoothness: peaks > 0 ? 1 - measures[peaksKey] / peaks : null,
  };
}

// the trade-off rule shared by the tracing exercises: a try that reached its
// target still isn't a hit if it got slower or shakier than recent tries.
function judge(counted, reachedTarget, vs, measures, extra = {}, shakierLimit = SHAKIER_LIMIT) {
  const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
  const shakier = vs.smoothness != null && vs.smoothness < -shakierLimit;
  return { counted, reachedTarget, slower, shakier, hit: reachedTarget && !slower && !shakier, measures, vs, ...extra };
}

// geometry: { baselineY, targetPx } in CSS px. recent: measures of the
// person's recent counted tries at this exercise, newest first.
export function scoreBigWriting(samples, strokeStarts, { baselineY, targetPx }, recent = []) {
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
    size: loops ? median(tops) / targetPx : NaN,
    // share of loops that touched the line.
    accuracy: loops ? reached / loops : NaN,
    // how much the last third of the row shrank (negative) or grew against the first third.
    shrink: third >= 2 ? mean(tops.slice(-third)) / mean(tops.slice(0, third)) - 1 : NaN,
    pace: motion.penDown > 0 ? loops / motion.penDown : NaN,
    peaksPerLoop: loops ? motion.peaks / loops : NaN,
  };
  const counted = loops >= MIN_LOOPS && measures.pace > 0;
  const vs = counted ? compareRecent(measures, recent) : { pace: null, smoothness: null };
  const reachedTarget = counted && measures.accuracy >= HIT_SHARE;
  const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
  const shakier = vs.smoothness != null && vs.smoothness < -SHAKIER_LIMIT;
  // where each loop topped out, for marking on the writing. not saved.
  const marks = found.map((l) => ({ x: l.x, y: l.y, reached: reachesLine(l, targetPx) }));
  return { counted, reachedTarget, slower, shakier, hit: reachedTarget && !slower && !shakier, measures, vs, marks };
}

// ---------- paths to follow (steady tracing, rhythm) ----------
// a path is its points plus the distance along it to each one, in CSS px.
export function makePath(points) {
  const x = points.map((p) => p[0]), y = points.map((p) => p[1]), s = [0];
  for (let i = 1; i < points.length; i++) s.push(s[i - 1] + Math.hypot(x[i] - x[i - 1], y[i] - y[i - 1]));
  return { x, y, s, length: s[s.length - 1] };
}

// the closest point on the path to (px, py): how far away it is (dist) and
// how far along the path it sits (along).
export function nearestOnPath(path, px, py) {
  let dist = Infinity, along = 0;
  for (let i = 1; i < path.x.length; i++) {
    const ax = path.x[i - 1], ay = path.y[i - 1], dx = path.x[i] - ax, dy = path.y[i] - ay;
    const len2 = dx * dx + dy * dy;
    const f = len2 ? Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / len2)) : 0;
    const d = Math.hypot(px - ax - f * dx, py - ay - f * dy);
    if (d < dist) { dist = d; along = path.s[i - 1] + f * Math.sqrt(len2); }
  }
  return { dist, along };
}

// the point `along` px down the path.
export function pointAlong(path, along) {
  const a = Math.min(Math.max(along, 0), path.length);
  let i = 1;
  while (i < path.s.length - 1 && path.s[i] < a) i++;
  const span = path.s[i] - path.s[i - 1], f = span ? (a - path.s[i - 1]) / span : 0;
  return [path.x[i - 1] + f * (path.x[i] - path.x[i - 1]), path.y[i - 1] + f * (path.y[i] - path.y[i - 1])];
}

// the path is cut into this many equal pieces; a piece counts as traced when
// the pen passed close to it.
export const COVER_PIECES = 40;
function coverage(nearest, length, closePx) {
  const done = new Set();
  for (const n of nearest) if (n.dist <= closePx) done.add(Math.min(COVER_PIECES - 1, Math.floor((n.along / length) * COVER_PIECES)));
  return done.size / COVER_PIECES;
}

// ---------- steady tracing ----------
// watch a dot trace a spiral, picture drawing it, then trace it while the
// guide fades with each level.
export const TRACE_TURNS = 3;
// a hit: at least this share of the spiral traced...
export const TRACE_COVER = 0.9;
// ...staying this close to it on average, as a share of its radius.
export const TRACE_LIMIT = 0.05;
// less than this share traced and the try is too short to judge.
export const TRACE_MIN_COVER = 0.5;

// the spiral, centred in a w x h area, starting from the middle.
export function tracingPath(w, h) {
  const radius = Math.min(w, h) / 2 - 24, n = 600, pts = [];
  for (let i = 0; i <= n; i++) {
    const p = i / n, th = p * TRACE_TURNS * 2 * Math.PI;
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
    // average distance from the guide as a share of the spiral's radius.
    accuracy: distPx / path.radius,
    // spiral radii traced per second, to make pace more comparable across canvas sizes.
    pace: motion.penDown > 0 ? (cover * path.length) / path.radius / motion.penDown : NaN,
    peaksPerTurn: turns > 0 ? motion.peaks / turns : NaN,
  };
  const counted = cover >= TRACE_MIN_COVER && measures.pace > 0;
  const vs = counted ? compareRecent(measures, recent, "peaksPerTurn") : { pace: null, smoothness: null };
  return judge(counted, counted && cover >= TRACE_COVER && measures.accuracy <= TRACE_LIMIT, vs, measures, {
    limitPx: TRACE_LIMIT * path.radius,
  });
}

// ---------- rhythm ----------
// trace a wave while keeping up with a dot that moves to a metronome: one
// beat for each rise or fall. the tempo goes up with each level.
export const RHYTHM_BEATS = 8;
// beats counted in before the dot sets off.
export const COUNT_IN = 3;
// a hit: at least this share of the wave traced...
export const RHYTHM_COVER = 0.85;
// ...keeping within this many beats of the dot on average...
export const RHYTHM_LAG = 0.5;
// ...and this close to the wave, as a share of its height.
export const RHYTHM_NEAR = 0.25;
export const RHYTHM_MIN_COVER = 0.4;

// the wave across a w x h area. it starts at the bottom left; beat k ends at
// along = k * beatLength, a top or a bottom.
export function rhythmPath(w, h) {
  const left = 0.08 * w, right = 0.92 * w, mid = h / 2, amp = 0.3 * h, n = 60 * RHYTHM_BEATS, pts = [];
  for (let i = 0; i <= n; i++) {
    const p = i / n;
    pts.push([left + p * (right - left), mid + amp * Math.cos(Math.PI * p * RHYTHM_BEATS)]);
  }
  const path = makePath(pts);
  return { ...path, height: 2 * amp, beatLength: path.length / RHYTHM_BEATS };
}

// smoothness for rhythm. following a moving dot means speeding up and slowing
// down along the wave all the time, so speed peaks would count good tracking
// as shaky. instead: side-to-side wobble, how far the pen strays across the
// wave and back within WOBBLE_SECS, RMS in CSS px, while the dot is moving.
export const WOBBLE_SECS = 0.25;
// chosen tolerance: rhythm counts as shakier when wobble is more than 50%
// above the recent median.
export const RHYTHM_SHAKIER_LIMIT = 0.5;

function wobble(samples, strokeStarts, path, nearest, moving) {
  // signed distance from the wave: + on one side, - on the other.
  const side = samples.map((p, i) => {
    const a = pointAlong(path, nearest[i].along - 1), b = pointAlong(path, nearest[i].along + 1);
    return Math.sign((b[0] - a[0]) * (p.y - a[1]) - (b[1] - a[1]) * (p.x - a[0])) * nearest[i].dist;
  });
  const bounds = [...strokeStarts, samples.length];
  const half = Math.round((WOBBLE_SECS * 60) / 2);
  let sum = 0, count = 0;
  for (let k = 0; k < bounds.length - 1; k++) {
    const a = bounds[k], b = bounds[k + 1];
    if (b - a < 2) continue;
    // resample at 60 Hz so different input sample rates are more comparable.
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
      sum += (r[i] - mean(r.slice(Math.max(0, i - half), i + half + 1))) ** 2;
      count++;
    }
  }
  return count ? Math.sqrt(sum / count) : NaN;
}

// timing: { beatSec, penOffset } - penOffset is the time from the dot setting
// off to the pen's first sample, in seconds (negative if the pen was down first).
export function scoreRhythm(samples, strokeStarts, path, { beatSec, penOffset }, recent = []) {
  const nearest = samples.map((p) => nearestOnPath(path, p.x, p.y));
  const end = RHYTHM_BEATS * beatSec;
  const lags = [];
  samples.forEach((p, i) => {
    const t = p.t + penOffset; // seconds since the dot set off
    if (t < 0 || t > end) return;
    // + ahead of the dot, - behind it, in beats.
    lags.push(nearest[i].along / path.beatLength - t / beatSec);
  });
  const cover = coverage(nearest, path.length, 0.2 * path.height);
  const motion = motionMeasures(samples, strokeStarts);
  const beats = RHYTHM_BEATS * cover;
  const moving = (t) => t + penOffset >= 0 && t + penOffset <= end;
  const measures = {
    cover,
    // how far from the dot, in beats, ignoring ahead or behind.
    lag: lags.length ? mean(lags.map(Math.abs)) : NaN,
    // the same with its sign: + ahead of the dot, - behind.
    lead: lags.length ? mean(lags) : NaN,
    near: nearest.length ? mean(nearest.map((n) => n.dist)) / path.height : NaN,
    peaksPerBeat: beats > 0 ? motion.peaks / beats : NaN,
    // side-to-side wobble while the dot moved, CSS px (see WOBBLE_SECS).
    wobble: wobble(samples, strokeStarts, path, nearest, moving),
  };
  const counted = cover >= RHYTHM_MIN_COVER && lags.length >= 10;
  // the metronome sets the pace, so only smoothness is compared with recent tries.
  const vs = counted ? { pace: null, smoothness: compareRecent(measures, recent, "wobble").smoothness } : { pace: null, smoothness: null };
  const reached = counted && cover >= RHYTHM_COVER && measures.lag <= RHYTHM_LAG && measures.near <= RHYTHM_NEAR;
  return judge(counted, reached, vs, measures, {}, RHYTHM_SHAKIER_LIMIT);
}

// ---------- hand skills: shrinking targets ----------
// targets appear one at a time and shrink away; tap each before it's gone.
// each level starts them smaller.
export const TARGETS = 15;
// a target shrinks from its starting size to nothing in this many seconds.
export const SHRINK_SECS = 2;
// a hit: at least this share of targets caught...
export const CATCH_SHARE = 0.8;
// ...with at least this share of all taps landing on a circle, so tapping
// everywhere doesn't count as catching.
export const TAP_PRECISION = 0.8;

// the target's radius `secs` after it appeared, 0 once it's gone.
export const targetRadius = (startSize, secs) => Math.max(0, (startSize / 2) * (1 - secs / SHRINK_SECS));

// results: one { caught, ms } per target, ms from appearing to the catching
// tap. extraTaps: taps that missed every target. the clock sets the pace, so
// nothing is compared with recent tries.
export function scoreTargets(results, extraTaps) {
  const caught = results.filter((r) => r.caught);
  const measures = {
    targets: results.length,
    caught: caught.length,
    extraTaps,
    reactionMs: caught.length ? median(caught.map((r) => r.ms)) : NaN,
    // share of all taps that caught a circle.
    precision: caught.length + extraTaps ? caught.length / (caught.length + extraTaps) : 0,
  };
  const counted = results.length >= TARGETS;
  const reached = counted && caught.length / results.length >= CATCH_SHARE && measures.precision >= TAP_PRECISION;
  return judge(counted, reached, { pace: null, smoothness: null }, measures);
}
