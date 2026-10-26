// TRAIN.JS HOLDS THE PRACTICE EXERCISES
// IT HAS THE LEVEL RULE, EACH EXERCISE'S LEVELS AND THE MEASURES TAKEN ON EVERY TRY
// THE FUNCTIONS DON'T TOUCH THE PAGE, SO NODE TESTS THEM WITH TOOLS/TRAIN-CHECK.MJS AND THE IPAD APP RUNS THEM THROUGH JAVASCRIPTCORE


// THE LEVEL RULE

// 3 hits at a level move up one level, and 3 misses in a row move down one
export const HITS_TO_LEVEL_UP = 3;
export const MISSES_TO_LEVEL_DOWN = 3;

// A try that reached its target is still a miss if its pace or smoothness dropped more than this against recent tries
export const SLOWER_LIMIT = 0.15;
export const SHAKIER_LIMIT = 0.15;

// How many recent counted tries the pace and smoothness are compared with
export const RECENT_TRIES = 5;

// Each exercise's levels, from easy to hard
// An exercise with built: false shows in the Training tab but can't be opened
export const EXERCISES = {

  // The target line's height as a share of the writing area's height
  "big-writing": { built: true, levels: [0.2, 0.24, 0.28, 0.32, 0.36, 0.4, 0.45, 0.5, 0.55, 0.6] },

  // Beats per minute
  rhythm: { built: true, levels: [40, 45, 50, 55, 60, 66, 72, 80, 88, 96] },

  // How visible the guide is, where 1 is fully visible
  "steady-tracing": { built: true, levels: [1, 0.85, 0.7, 0.55, 0.45, 0.35, 0.25, 0.15, 0.08, 0] },

  // Each target's starting width in CSS px
  "hand-skills": { built: true, levels: [96, 84, 72, 64, 56, 48, 42, 36, 32, 28] },
};


// Make the starting level state, where level 0 is Level 1 and last is the most recent level change
export function newLevelState() {
  return { level: 0, hits: 0, misses: 0, last: null };
}


// Find the next level state after one judged try, where a try that didn't count changes nothing
export function applyTry(state, { counted, hit }, levelCount) {
  if (!counted) {
    return { state, change: null };
  }

  // A hit moves up a level once there are enough hits, unless this is the top level
  if (hit) {
    const hits = state.hits + 1;
    if (hits >= HITS_TO_LEVEL_UP && state.level < levelCount - 1) {
      return { state: { level: state.level + 1, hits: 0, misses: 0, last: "up" }, change: "up" };
    }

    // Otherwise count the hit and start the misses in a row over
    return { state: { ...state, hits: Math.min(hits, HITS_TO_LEVEL_UP), misses: 0 }, change: null };
  }

  // A miss moves down a level once there are enough misses in a row, unless this is Level 1
  const misses = state.misses + 1;
  if (misses >= MISSES_TO_LEVEL_DOWN && state.level > 0) {
    return { state: { level: state.level - 1, hits: 0, misses: 0, last: "down" }, change: "down" };
  }
  return { state: { ...state, misses: Math.min(misses, MISSES_TO_LEVEL_DOWN) }, change: null };
}


// Drop one level and reset the counts, where Level 1 stays as it is
export function tooHard(state) {
  if (state.level === 0) {
    return state;
  }
  return { level: state.level - 1, hits: 0, misses: 0, last: "down" };
}


// MEASURES TAKEN ON EVERY DRAWING

// Find the middle value of a list of numbers, or NaN for an empty list
function median(xs) {
  if (!xs.length) {
    return NaN;
  }
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  if (s.length % 2) {
    return s[m];
  }
  return (s[m - 1] + s[m]) / 2;
}


// Find the average of a list of numbers
function mean(xs) {
  let total = 0;
  for (const x of xs) {
    total += x;
  }
  return total / xs.length;
}


// A pen within this many px of where a stroke starts or ends isn't moving yet
export const STILL_PX = 4;


// Cut the time the pen sat still at the start and end of a stroke
export function trimStill(stroke) {

  // How far apart two points are
  function dist(p, q) {
    return Math.hypot(p.x - q.x, p.y - q.y);
  }

  // Move the start forward past the points still near the first one
  let a = 0;
  let b = stroke.length - 1;
  while (a < b && dist(stroke[a + 1], stroke[0]) < STILL_PX) {
    a++;
  }

  // Move the end back past the points still near the last one
  while (b > a && dist(stroke[b - 1], stroke[stroke.length - 1]) < STILL_PX) {
    b--;
  }
  return stroke.slice(a, b + 1);
}


// Find the time the pen was down and moving, the length of its path, and its number of speed peaks
// A speed peak is one speed up and slow down of the pen
export function motionMeasures(samples, strokeStarts = [0]) {
  const bounds = [...strokeStarts, samples.length];
  let penDown = 0;
  let length = 0;
  let peaks = 0;

  // Go through each stroke, leaving out the time the pen sat still at its ends
  for (let s = 0; s < bounds.length - 1; s++) {
    const stroke = trimStill(samples.slice(bounds[s], bounds[s + 1]));
    if (stroke.length < 2) {
      continue;
    }

    penDown += stroke[stroke.length - 1].t - stroke[0].t;
    for (let i = 1; i < stroke.length; i++) {
      length += Math.hypot(stroke[i].x - stroke[i - 1].x, stroke[i].y - stroke[i - 1].y);
    }
    peaks += speedPeaks(stroke);
  }
  return { penDown, length, peaks };
}


// Count the speed peaks in a stroke
// The stroke is sampled again at 60 Hz, and its speed is averaged over 5 samples
function speedPeaks(stroke) {
  const t0 = stroke[0].t;
  const t1 = stroke[stroke.length - 1].t;
  const step = 1 / 60;

  // Find the pen's position every 60th of a second, going between the two nearest samples
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
  if (pts.length < 5) {
    return 0;
  }

  // Find the speed between each pair of positions
  const raw = [];
  for (let i = 1; i < pts.length; i++) {
    const dx = pts[i][0] - pts[i - 1][0];
    const dy = pts[i][1] - pts[i - 1][1];
    raw.push(Math.hypot(dx, dy) / step);
  }

  // Average each speed with the two on each side
  const speed = [];
  for (let i = 0; i < raw.length; i++) {
    speed.push(mean(raw.slice(Math.max(0, i - 2), i + 3)));
  }

  // A peak only counts once the speed drops a quarter of the median speed below it
  const delta = 0.25 * median(speed);
  if (!(delta > 0)) {
    return 0;
  }

  // Count each time the speed rises to a peak and then drops by delta
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

  // A rise at the very end that never dropped still counts as a peak
  if (rising && best > low + delta) {
    return count + 1;
  }
  return count;
}


// BIG WRITING, WHERE THE USER WRITES A ROW OF TALL LOOPS LIKE CURSIVE L'S BETWEEN A BASELINE AND A TARGET LINE

// A loop touches the line when its top reaches this share of the target height
export const REACH = 0.9;

// The loop's height from its own bottom must also reach this share
export const OWN_REACH = 0.85;

// The share of found letters that must reach the line for a hit
export const HIT_SHARE = 0.75;

// The least number of found letters for a try to count
export const MIN_LOOPS = 4;

// A rise smaller than this share of the target height is never a loop
export const MIN_LOOP = 0.15;

// A letter whose top is less than this share of its height to the right of the last one is the last letter written over
export const MIN_STEP = 0.15;

// A letter is a loop if either of two things is true
// The first is that its down-stroke crosses or touches its up-stroke at least this share of its height below its top
export const CLOSE_DEPTH = 0.2;

// Strokes within this many CSS px count as touching, since mouse strokes often cross by sharing a pixel
export const TOUCH_PX = 1;

// The second is that near its top, its down-stroke runs no more than this share of its height right of its up-stroke
// That is averaged at 10, 20 and 30% of its height below the top, and spikes, teeth, humps and n's come down further right
export const BACK_LIMIT = 0.05;
const BACK_DEPTHS = [0.1, 0.2, 0.3];

// A letter's bottom can be at most this share of the target height below the drawn baseline
export const BELOW_LIMIT = 0.25;


// Find the peaks and troughs of the heights h, one after the other, each at least the drop distance from the one before
function turningPoints(h, drop) {
  const out = [];

  // Mode 1 is rising, -1 is falling and 0 is not known yet
  let mode = 0;
  let hi = 0;
  let lo = 0;
  for (let i = 1; i < h.length; i++) {

    // Keep the highest point while rising and the lowest while falling
    if (mode >= 0 && h[i] > h[hi]) {
      hi = i;
    }
    if (mode <= 0 && h[i] < h[lo]) {
      lo = i;
    }

    // Once the line drops far enough below the highest point it was a peak, and far enough above the lowest it was a trough
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

  // Add the last turn when the pen lifted at the top of the last loop or on the way down from it
  if (mode === 1 && out.length && h[hi] - h[out.at(-1).i] >= drop) {
    out.push({ i: hi, peak: true });
  }
  if (mode === -1) {
    out.push({ i: lo, peak: false });
  }
  return out;
}


// Check whether segment p1 to p2 crosses segment p3 to p4
function segmentsCross(p1, p2, p3, p4) {

  // Which side of the line through a and b the point c is on
  function side(a, b, c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }

  // They cross when each segment's ends are on opposite sides of the other one's line
  const crossesLine34 = side(p3, p4, p1) * side(p3, p4, p2) < 0;
  const crossesLine12 = side(p1, p2, p3) * side(p1, p2, p4) < 0;
  return crossesLine34 && crossesLine12;
}


// Find the shortest distance from point p to the segment from a to b
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


// Check whether two segments cross or come within TOUCH_PX of each other
function segmentsMeet(p1, p2, p3, p4) {
  if (segmentsCross(p1, p2, p3, p4)) {
    return true;
  }
  const closest = Math.min(
    toSegment(p1, p3, p4),
    toSegment(p2, p3, p4),
    toSegment(p3, p1, p2),
    toSegment(p4, p1, p2),
  );
  return closest <= TOUCH_PX;
}


// Check whether the stroke coming down from the top crosses or touches the stroke going up to it
// They have to meet at least CLOSE_DEPTH of the letter's height below the top, and segments across a pen lift are skipped
function closesAround(samples, h, lifts, from, top, to, own) {

  // The strokes must meet at or below this height
  const deep = h[top] - CLOSE_DEPTH * own;

  for (let i = from; i < top; i++) {

    // Skip pen lifts, and pieces of the up-stroke that are all above the meeting height
    if (lifts.has(i + 1)) {
      continue;
    }
    const ilo = Math.min(h[i], h[i + 1]);
    const ihi = Math.max(h[i], h[i + 1]);
    if (ilo > deep) {
      continue;
    }

    for (let j = top; j < to; j++) {
      if (lifts.has(j + 1)) {
        continue;
      }
      const jlo = Math.min(h[j], h[j + 1]);
      const jhi = Math.max(h[j], h[j + 1]);

      // Skip pieces too far apart in height to meet
      if (jlo > ihi + TOUCH_PX || ilo > jhi + TOUCH_PX) {
        continue;
      }

      // Skip pieces that would meet above the meeting height
      if ((h[i] + h[i + 1] + h[j] + h[j + 1]) / 4 > deep) {
        continue;
      }

      if (segmentsMeet(samples[i], samples[i + 1], samples[j], samples[j + 1])) {
        return true;
      }
    }
  }
  return false;
}


// Find up and down, the x where the line crosses the height level going up to the top and coming back down
// Each is found between the two nearest samples, and is null on a side that never gets that low
function sidesAt(samples, h, from, top, to, level) {

  // Find the x where the piece from sample a to sample b crosses the height level
  function at(a, b) {
    let f = 0;
    if (h[b] !== h[a]) {
      f = (level - h[a]) / (h[b] - h[a]);
    }
    return samples[a].x + f * (samples[b].x - samples[a].x);
  }

  // Walk down from the top on each side until the line is at or below the level
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


// Find how far right of its up-stroke a letter's down-stroke runs near its top, as a share of its height, averaged over BACK_DEPTHS
// It is below 0 when the down-stroke comes down to the left, and null when a side never gets that low
function backSide(samples, h, from, top, to, own) {
  const gaps = [];
  for (const f of BACK_DEPTHS) {
    const { up, down } = sidesAt(samples, h, from, top, to, h[top] - f * own);
    if (up == null || down == null) {
      return null;
    }
    gaps.push((down - up) / own);
  }
  return mean(gaps);
}


// Find every letter in a row of writing, loop or not, in CSS px
// Each letter has its top above the baseline, its height from its own bottom, its bottom, whether it's a loop and where its top is
export function findLoops(samples, baselineY, targetPx, strokeStarts = [0]) {
  if (samples.length < 2) {
    return [];
  }

  // Each point's height above the baseline, and the smallest rise that counts
  const h = [];
  for (const p of samples) {
    h.push(baselineY - p.y);
  }
  const drop = Math.max(6, MIN_LOOP * targetPx);

  // The writer's own baseline, the 10th percentile height
  const sorted = [...h].sort((p, q) => p - q);
  const base = sorted[Math.floor(0.1 * (sorted.length - 1))];

  // Go through the peaks and troughs, where valley is the lowest trough after the current letter's top
  const letters = [];
  let valley = null;
  for (const p of turningPoints(h, drop)) {
    if (!p.peak) {
      if (valley == null || h[p.i] < h[valley]) {
        valley = p.i;
      }
      continue;
    }

    const cur = letters.at(-1);
    if (cur && valley != null) {
      const lower = Math.min(h[cur.top], h[p.i]);
      const rise = lower - h[valley];

      // A top not far enough right of the last letter's top means the last letter was written over
      const over = samples[p.i].x - samples[cur.top].x < MIN_STEP * rise;

      // A write-over, or a dip less than halfway back down to the baseline, is the same letter
      if (over || rise < 0.5 * (lower - base)) {
        if (h[p.i] > h[cur.top]) {
          cur.top = p.i;
        }
        valley = null;
        continue;
      }
      cur.after = valley;
    }

    // Start a new letter at this top
    letters.push({ top: p.i, before: valley, after: null });
    valley = null;
  }
  if (letters.length) {
    letters.at(-1).after = valley;
  }

  // Measure each letter, and keep the ones that rose far enough
  const lifts = new Set(strokeStarts);
  const out = [];
  for (const { top, before, after } of letters) {

    // A letter runs from the trough before it to the trough after it, or to the ends of the row
    let from = before;
    if (from === null || from === undefined) {
      from = 0;
    }
    let to = after;
    if (to === null || to === undefined) {
      to = samples.length - 1;
    }

    const bottom = Math.min(h[from], h[to]);
    const own = h[top] - bottom;
    const closed = closesAround(samples, h, lifts, from, top, to, own);
    const back = backSide(samples, h, from, top, to, own);
    const loop = closed || (back != null && back <= BACK_LIMIT);
    if (own >= drop) {
      out.push({ i: top, top: h[top], own, bottom, closed, back, loop, x: samples[top].x, y: samples[top].y });
    }
  }
  return out;
}


// Check whether a loop reached the line from a base on the baseline
export function reachesLine(loop, targetPx) {
  const onBaseline = loop.bottom >= -BELOW_LIMIT * targetPx;
  const tallEnough = loop.top >= REACH * targetPx && loop.own >= OWN_REACH * targetPx;
  return loop.loop && onBaseline && tallEnough;
}


// Compare pace and smoothness with the median of recent counted tries, as shares where 0.1 means 10% more
// Each is null when there's nothing to compare, and peaksKey names the exercise's smoothness measure, where lower is smoother
export function compareRecent(measures, recent, peaksKey = "peaksPerLoop") {
  const prev = recent.slice(0, RECENT_TRIES);
  if (!prev.length) {
    return { pace: null, smoothness: null };
  }

  // Get one measure from each recent try, leaving out tries saved before that measure existed
  function known(key) {
    const values = [];
    for (const m of prev) {
      if (Number.isFinite(m[key])) {
        values.push(m[key]);
      }
    }
    return values;
  }

  const pace = median(known("pace"));
  const peaks = median(known(peaksKey));

  let paceVs = null;
  if (pace > 0) {
    paceVs = measures.pace / pace - 1;
  }

  // Lower values count as smoother
  let smoothness = null;
  if (peaks > 0) {
    smoothness = 1 - measures[peaksKey] / peaks;
  }

  return { pace: paceVs, smoothness };
}


// The hit rule for the exercises, where a try that reached its target is still a miss if it got slower or shakier
function judge(counted, reachedTarget, vs, measures, extra = {}, shakierLimit = SHAKIER_LIMIT) {
  const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
  const shakier = vs.smoothness != null && vs.smoothness < -shakierLimit;
  const hit = reachedTarget && !slower && !shakier;
  return { counted, reachedTarget, slower, shakier, hit, measures, vs, ...extra };
}


// Score one big writing try, where recent holds the measures of recent counted tries, newest first
export function scoreBigWriting(samples, strokeStarts, { baselineY, targetPx }, recent = []) {
  const found = findLoops(samples, baselineY, targetPx, strokeStarts);
  const motion = motionMeasures(samples, strokeStarts);
  const loops = found.length;

  // Each letter's height, and how many reached the line, weren't loops, or dipped well below the baseline
  const tops = [];
  let reached = 0;
  let open = 0;
  let below = 0;
  for (const l of found) {
    tops.push(l.own);
    if (reachesLine(l, targetPx)) {
      reached++;
    }
    if (!l.loop) {
      open++;
    }
    if (l.loop && l.bottom < -BELOW_LIMIT * targetPx) {
      below++;
    }
  }

  // The last third of the row against the first third, below 0 when it shrank
  const third = Math.floor(loops / 3);
  let shrink = NaN;
  if (third >= 2) {
    shrink = mean(tops.slice(-third)) / mean(tops.slice(0, third)) - 1;
  }

  // The median letter height against the target height, and the share of letters that reached the line
  let size = NaN;
  let accuracy = NaN;
  let peaksPerLoop = NaN;
  if (loops) {
    size = median(tops) / targetPx;
    accuracy = reached / loops;
    peaksPerLoop = motion.peaks / loops;
  }

  // Loops a second while the pen was moving
  let pace = NaN;
  if (motion.penDown > 0) {
    pace = loops / motion.penDown;
  }

  // open is letters shaped like a spike, hump or arch, and below is loops whose base dipped well below the baseline
  const measures = {
    loops,
    reached,
    open,
    below,
    size,
    accuracy,
    shrink,
    pace,
    peaksPerLoop,
  };

  // Only compare with recent tries when this try counts
  const counted = loops >= MIN_LOOPS && measures.pace > 0;
  let vs = { pace: null, smoothness: null };
  if (counted) {
    vs = compareRecent(measures, recent);
  }

  const reachedTarget = counted && measures.accuracy >= HIT_SHARE;
  const slower = vs.pace != null && vs.pace < -SLOWER_LIMIT;
  const shakier = vs.smoothness != null && vs.smoothness < -SHAKIER_LIMIT;

  // Where each loop topped out, for the marks on the writing, which aren't saved
  const marks = [];
  for (const l of found) {
    marks.push({ x: l.x, y: l.y, reached: reachesLine(l, targetPx) });
  }

  const hit = reachedTarget && !slower && !shakier;
  return { counted, reachedTarget, slower, shakier, hit, measures, vs, marks };
}


// PATHS TO FOLLOW IN STEADY TRACING AND RHYTHM

// Make a path from its points, with the distance along it to each one, in CSS px
export function makePath(points) {
  const x = [];
  const y = [];
  for (const p of points) {
    x.push(p[0]);
    y.push(p[1]);
  }

  const s = [0];
  for (let i = 1; i < points.length; i++) {
    s.push(s[i - 1] + Math.hypot(x[i] - x[i - 1], y[i] - y[i - 1]));
  }
  return { x, y, s, length: s[s.length - 1] };
}


// Find the closest point on the path to px, py, with how far away it is and how far along the path
export function nearestOnPath(path, px, py) {
  let dist = Infinity;
  let along = 0;
  for (let i = 1; i < path.x.length; i++) {

    // The closest point on this piece of the path
    const ax = path.x[i - 1];
    const ay = path.y[i - 1];
    const dx = path.x[i] - ax;
    const dy = path.y[i] - ay;
    const len2 = dx * dx + dy * dy;
    let f = 0;
    if (len2) {
      f = Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / len2));
    }

    // Keep it if it is the closest so far
    const d = Math.hypot(px - ax - f * dx, py - ay - f * dy);
    if (d < dist) {
      dist = d;
      along = path.s[i - 1] + f * Math.sqrt(len2);
    }
  }
  return { dist, along };
}


// Find the point a distance along the path, kept between its start and its end
export function pointAlong(path, along) {
  const a = Math.min(Math.max(along, 0), path.length);

  // Find the piece of the path the distance falls in
  let i = 1;
  while (i < path.s.length - 1 && path.s[i] < a) {
    i++;
  }

  // Go the right share of the way along that piece
  const span = path.s[i] - path.s[i - 1];
  let f = 0;
  if (span) {
    f = (a - path.s[i - 1]) / span;
  }
  const x = path.x[i - 1] + f * (path.x[i] - path.x[i - 1]);
  const y = path.y[i - 1] + f * (path.y[i] - path.y[i - 1]);
  return [x, y];
}


// The path is cut into this many equal pieces, and a piece counts as traced when the pen passed close to it
export const COVER_PIECES = 40;


// Find the share of the path's pieces that the pen passed within closePx of
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


// STEADY TRACING, WHERE THE USER TRACES A SPIRAL WHILE ITS GUIDE FADES

// How many turns the spiral has
export const TRACE_TURNS = 3;

// A hit traces at least this share of the spiral
export const TRACE_COVER = 0.9;

// A hit stays this close to the spiral on average, as a share of its radius
export const TRACE_LIMIT = 0.05;

// With less than this share traced the try doesn't count
export const TRACE_MIN_COVER = 0.5;


// Make the spiral, centered in a w by h area and starting from the middle
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


// Score one steady tracing try
export function scoreTracing(samples, strokeStarts, path, recent = []) {

  // Find the closest point on the spiral to every sample, and how much of the spiral was traced
  const nearest = [];
  for (const p of samples) {
    nearest.push(nearestOnPath(path, p.x, p.y));
  }
  const cover = coverage(nearest, path.length, 0.12 * path.radius);

  // The average distance from the spiral
  let distPx = NaN;
  if (nearest.length) {
    const dists = [];
    for (const n of nearest) {
      dists.push(n.dist);
    }
    distPx = mean(dists);
  }

  const motion = motionMeasures(samples, strokeStarts);
  const turns = TRACE_TURNS * cover;

  // Spiral radii traced per second, which is the same on any canvas size
  let pace = NaN;
  if (motion.penDown > 0) {
    pace = (cover * path.length) / path.radius / motion.penDown;
  }

  let peaksPerTurn = NaN;
  if (turns > 0) {
    peaksPerTurn = motion.peaks / turns;
  }

  // accuracy is the average distance from the guide as a share of the spiral's radius
  const measures = {
    cover,
    distPx,
    accuracy: distPx / path.radius,
    pace,
    peaksPerTurn,
  };

  // Only compare with recent tries when this try counts
  const counted = cover >= TRACE_MIN_COVER && measures.pace > 0;
  let vs = { pace: null, smoothness: null };
  if (counted) {
    vs = compareRecent(measures, recent, "peaksPerTurn");
  }

  const reached = counted && cover >= TRACE_COVER && measures.accuracy <= TRACE_LIMIT;
  return judge(counted, reached, vs, measures, { limitPx: TRACE_LIMIT * path.radius });
}


// RHYTHM, WHERE THE USER TRACES A WAVE IN TIME WITH A DOT THAT MOVES TO A METRONOME

// How many beats the wave has
export const RHYTHM_BEATS = 8;

// Lead-in beats before the dot sets off
export const COUNT_IN = 3;

// A hit traces at least this share of the wave
export const RHYTHM_COVER = 0.85;

// A hit stays within this many beats of the dot on average
export const RHYTHM_LAG = 0.5;

// A hit stays this close to the wave on average, as a share of its height
export const RHYTHM_NEAR = 0.25;

// With less than this share traced the try doesn't count
export const RHYTHM_MIN_COVER = 0.4;


// Make the wave across a w by h area, starting at the bottom left
// Beat k ends at along = k * beatLength, on a top or a bottom
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


// Rhythm's smoothness is side to side wobble instead of speed peaks, which is how far the pen strays across the wave and back
// It is measured within this many seconds, as an RMS in CSS px, while the dot is moving
export const WOBBLE_SECS = 0.25;

// Wobble more than 50% above the recent median counts as shakier
export const RHYTHM_SHAKIER_LIMIT = 0.5;


// Find how much the pen wobbled from side to side across the wave while the dot was moving
function wobble(samples, strokeStarts, path, nearest, moving) {

  // Each sample's distance from the wave, above 0 on one side and below 0 on the other
  const side = [];
  for (let i = 0; i < samples.length; i++) {
    const p = samples[i];
    const a = pointAlong(path, nearest[i].along - 1);
    const b = pointAlong(path, nearest[i].along + 1);
    const cross = (b[0] - a[0]) * (p.y - a[1]) - (b[1] - a[1]) * (p.x - a[0]);
    side.push(Math.sign(cross) * nearest[i].dist);
  }

  const bounds = [...strokeStarts, samples.length];
  const half = Math.round((WOBBLE_SECS * 60) / 2);
  let sum = 0;
  let count = 0;
  for (let k = 0; k < bounds.length - 1; k++) {
    const a = bounds[k];
    const b = bounds[k + 1];
    if (b - a < 2) {
      continue;
    }

    // Find the side distance every 60th of a second, going between the two nearest samples
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

    // Add up how far the side distance strays from its own moving average, only while the dot moves
    for (let i = 0; i < r.length; i++) {
      if (!moving(ts[i])) {
        continue;
      }
      const around = mean(r.slice(Math.max(0, i - half), i + half + 1));
      sum += (r[i] - around) ** 2;
      count++;
    }
  }

  // Give back the RMS of that, or NaN if the dot never moved under the pen
  if (count) {
    return Math.sqrt(sum / count);
  }
  return NaN;
}


// Score one rhythm try
// timing is { beatSec, penOffset }, where penOffset is seconds from the dot setting off to the pen's first sample,
// and below 0 when the pen was down first
export function scoreRhythm(samples, strokeStarts, path, { beatSec, penOffset }, recent = []) {

  // Find the closest point on the wave to every sample
  const nearest = [];
  for (const p of samples) {
    nearest.push(nearestOnPath(path, p.x, p.y));
  }
  const end = RHYTHM_BEATS * beatSec;

  // Find how many beats ahead of the dot the pen was at each sample while the dot moved, below 0 when behind it
  const lags = [];
  for (let i = 0; i < samples.length; i++) {

    // Seconds after the dot set off
    const t = samples[i].t + penOffset;
    if (t < 0 || t > end) {
      continue;
    }
    lags.push(nearest[i].along / path.beatLength - t / beatSec);
  }

  const cover = coverage(nearest, path.length, 0.2 * path.height);
  const motion = motionMeasures(samples, strokeStarts);
  const beats = RHYTHM_BEATS * cover;

  // Check whether the dot was moving at the pen's time t
  function moving(t) {
    return t + penOffset >= 0 && t + penOffset <= end;
  }

  // lag is beats from the dot ignoring ahead or behind, and lead is the same with its sign
  let lag = NaN;
  let lead = NaN;
  if (lags.length) {
    const sizes = [];
    for (const l of lags) {
      sizes.push(Math.abs(l));
    }
    lag = mean(sizes);
    lead = mean(lags);
  }

  // The average distance from the wave as a share of its height
  let near = NaN;
  if (nearest.length) {
    const dists = [];
    for (const n of nearest) {
      dists.push(n.dist);
    }
    near = mean(dists) / path.height;
  }

  let peaksPerBeat = NaN;
  if (beats > 0) {
    peaksPerBeat = motion.peaks / beats;
  }

  // wobble is the side to side wobble while the dot moved, in CSS px
  const measures = {
    cover,
    lag,
    lead,
    near,
    peaksPerBeat,
    wobble: wobble(samples, strokeStarts, path, nearest, moving),
  };

  // Only smoothness is compared with recent tries, since the metronome sets the pace
  const counted = cover >= RHYTHM_MIN_COVER && lags.length >= 10;
  let smoothness = null;
  if (counted) {
    smoothness = compareRecent(measures, recent, "wobble").smoothness;
  }
  const vs = { pace: null, smoothness };

  const reached =
    counted &&
    cover >= RHYTHM_COVER &&
    measures.lag <= RHYTHM_LAG &&
    measures.near <= RHYTHM_NEAR;
  return judge(counted, reached, vs, measures, {}, RHYTHM_SHAKIER_LIMIT);
}


// HAND SKILLS, WHERE THE USER TAPS EACH SHRINKING TARGET BEFORE IT'S GONE

// How many targets a try has
export const TARGETS = 15;

// Seconds for a target to shrink from its starting size to nothing
export const SHRINK_SECS = 2;

// A hit catches at least this share of the targets
export const CATCH_SHARE = 0.8;

// A hit needs at least this share of all taps to land on a target
export const TAP_PRECISION = 0.8;


// Find a target's radius secs seconds after it appeared, which is 0 once it's gone
export function targetRadius(startSize, secs) {
  return Math.max(0, (startSize / 2) * (1 - secs / SHRINK_SECS));
}


// Score one hand skills try
// Each result is { caught, ms } for one target, where ms is the time from appearing to the catching tap
// extraTaps counts the taps that missed every target
export function scoreTargets(results, extraTaps) {
  const caught = [];
  for (const r of results) {
    if (r.caught) {
      caught.push(r);
    }
  }
  const taps = caught.length + extraTaps;

  // The median time to catch a target
  let reactionMs = NaN;
  if (caught.length) {
    const times = [];
    for (const r of caught) {
      times.push(r.ms);
    }
    reactionMs = median(times);
  }

  // The share of all taps that caught a target
  let precision = 0;
  if (taps) {
    precision = caught.length / taps;
  }

  const measures = {
    targets: results.length,
    caught: caught.length,
    extraTaps,
    reactionMs,
    precision,
  };

  // Nothing is compared with recent tries, since the clock sets the pace
  const counted = results.length >= TARGETS;
  const reached =
    counted &&
    caught.length / results.length >= CATCH_SHARE &&
    measures.precision >= TAP_PRECISION;
  return judge(counted, reached, { pace: null, smoothness: null }, measures);
}