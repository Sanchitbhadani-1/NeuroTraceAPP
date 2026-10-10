// assert-based check for train.js: the level rule and the big-writing
// measures, on made-up drawings with known answers. run from the repo root:
//   node app/tools/train-check.mjs

import assert from "node:assert/strict";
import {
  applyTry, tooHard, newLevelState, findLoops, scoreBigWriting, compareRecent,
  HITS_TO_LEVEL_UP, MISSES_TO_LEVEL_DOWN, EXERCISES,
  tracingPath, scoreTracing, rhythmPath, scoreRhythm, pointAlong, scoreTargets, targetRadius,
  TRACE_TURNS, RHYTHM_BEATS, TARGETS, SHRINK_SECS,
} from "../train.js";
import { cursiveRow, letterRow, mouseLike, SHAPES } from "./handwriting.mjs";

const LEVELS = EXERCISES["big-writing"].levels.length;
const hit = { counted: true, hit: true }, miss = { counted: true, hit: false }, skip = { counted: false, hit: false };
const run = (state, tries) => tries.reduce((s, t) => applyTry(s, t, LEVELS).state, state);

// --- level rule -----------------------------------------------------------
assert.equal(HITS_TO_LEVEL_UP, 3);
assert.equal(MISSES_TO_LEVEL_DOWN, 3);
let s = run(newLevelState(), [hit, hit]);
assert.deepEqual(s, { level: 0, hits: 2, misses: 0, last: null });
let r = applyTry(s, hit, LEVELS);
assert.equal(r.change, "up");
assert.deepEqual(r.state, { level: 1, hits: 0, misses: 0, last: "up" });
// hits don't have to be in a row, misses do
s = run({ level: 1, hits: 0, misses: 0, last: null }, [miss, miss, hit]);
assert.deepEqual(s, { level: 1, hits: 1, misses: 0, last: null });
r = applyTry(run({ level: 1, hits: 1, misses: 0, last: null }, [miss, miss]), miss, LEVELS);
assert.equal(r.change, "down");
assert.deepEqual(r.state, { level: 0, hits: 0, misses: 0, last: "down" });
// floor and ceiling
s = run(newLevelState(), [miss, miss, miss, miss]);
assert.equal(s.level, 0);
s = run({ level: LEVELS - 1, hits: 0, misses: 0, last: null }, [hit, hit, hit, hit]);
assert.equal(s.level, LEVELS - 1);
// a try that didn't count changes nothing
assert.deepEqual(applyTry({ level: 2, hits: 1, misses: 2, last: null }, skip, LEVELS).state, { level: 2, hits: 1, misses: 2, last: null });
// too hard today
assert.deepEqual(tooHard({ level: 3, hits: 2, misses: 1, last: "up" }), { level: 2, hits: 0, misses: 0, last: "down" });
assert.deepEqual(tooHard(newLevelState()), newLevelState());

// --- big writing ------------------------------------------------------------
// a row of n loops, each `height` px tall above a baseline at y = 300, one
// loop every `secs` seconds, sampled at 120 Hz. `wobble` adds a fast shake.
// closed: false draws humps that go up and straight back down instead.
function loops({ n = 8, height = 120, secs = 0.8, wobble = 0, closed = true }) {
  const samples = [];
  const dt = 1 / 120, total = n * secs, back = closed ? (1.7 * 600) / n / (2 * Math.PI) : 0;
  for (let t = 0; t <= total + 1e-9; t += dt) {
    const phase = (t / secs) % 1;
    const shake = wobble * Math.sin(2 * Math.PI * 9 * t);
    samples.push({
      t,
      x: 20 + (t / total) * 600 + back * Math.sin(2 * Math.PI * phase),
      y: 300 - height * (0.5 - 0.5 * Math.cos(2 * Math.PI * phase)) + shake,
    });
  }
  return samples;
}
const geo = { baselineY: 300, targetPx: 120 };

const tops = findLoops(loops({}), 300, 120).map((l) => l.own);
assert.equal(tops.length, 8);
for (const h of tops) assert.ok(Math.abs(h - 120) < 2, `loop top ${h}`);

// reaching the line, nothing to compare with yet: a hit on the target alone
const tall = scoreBigWriting(loops({}), [0], geo);
assert.ok(tall.counted && tall.reachedTarget && tall.hit, JSON.stringify(tall));
assert.equal(tall.measures.reached, 8);
assert.ok(Math.abs(tall.measures.pace - 1.25) < 0.05, `pace ${tall.measures.pace}`);
assert.ok(tall.measures.peaksPerLoop >= 1.5 && tall.measures.peaksPerLoop <= 2.5, `peaks/loop ${tall.measures.peaksPerLoop}`);
assert.equal(compareRecent(tall.measures, []).pace, null);

// half-height loops miss the line
const small = scoreBigWriting(loops({ height: 60 }), [0], geo);
assert.ok(small.counted && !small.reachedTarget && !small.hit);
assert.equal(small.measures.reached, 0);

// three loops is too short to judge
assert.equal(scoreBigWriting(loops({ n: 3 }), [0], geo).counted, false);

// the trade-off: the same tall loops at half the pace reach the line but don't count
const recent = [tall.measures, tall.measures, tall.measures];
const slow = scoreBigWriting(loops({ secs: 1.6 }), [0], geo, recent);
assert.ok(slow.reachedTarget && slow.slower && !slow.hit, JSON.stringify(slow.vs));
assert.ok(Math.abs(slow.vs.pace + 0.5) < 0.05);

// a shaky try at the same pace reaches the line but doesn't count either
const shaky = scoreBigWriting(loops({ wobble: 6 }), [0], geo, recent);
assert.ok(shaky.reachedTarget && shaky.shakier && !shaky.hit, JSON.stringify(shaky.vs));

// the same try again compares as unchanged
const same = scoreBigWriting(loops({}), [0], geo, recent);
assert.ok(same.hit && Math.abs(same.vs.pace) < 0.01 && Math.abs(same.vs.smoothness) < 0.01);

// loops shrinking along the row show up as a negative shrink
const shrinking = loops({ n: 9 }).map((p, i, all) => ({ ...p, y: 300 - (300 - p.y) * (1 - 0.4 * (p.t / all.at(-1).t)) }));
assert.ok(scoreBigWriting(shrinking, [0], geo).measures.shrink < -0.2);

// --- realistic handwriting (tools/handwriting.mjs) ----------------------------
// slanted cursive l's sampled like an Apple Pencil. each case states what a
// person would do and what the score must still get right.
const real = (opts, recent = []) => {
  const { samples, strokeStarts } = cursiveRow(opts);
  return scoreBigWriting(samples, strokeStarts, geo, recent);
};
const near = (a, b, tol, what) => assert.ok(Math.abs(a - b) <= tol, `${what}: ${a} vs ${b}`);

const plain = real({});
assert.equal(plain.measures.loops, 8);
near(plain.measures.size, 1, 0.05, "size");
near(plain.measures.pace, 1 / 0.7, 0.05, "pace");
assert.ok(plain.hit);
assert.equal(plain.marks.length, 8);
assert.ok(plain.marks.every((m) => m.reached && Number.isFinite(m.x) && Number.isFinite(m.y)));

// every loop is found whatever the size, speed, slant, pen lifts or sampling rate
for (const opts of [{ height: 240 }, { height: 60 }, { height: 36 }, { loopSecs: 0.45 }, { loopSecs: 1.2 }, { slant: 0 },
  { slant: 0.6 }, { liftEvery: 3 }, { liftEvery: 1 }, { jitter: 1.5 }, { n: 12 }, { hz: 60 }, { seed: 2 }, { seed: 3 }]) {
  assert.equal(real(opts).measures.loops, opts.n ?? 8, JSON.stringify(opts));
}

// resting the Pencil for a second before and after isn't slow writing
near(real({ rest: 1 }).measures.pace, 1 / 0.7, 0.05, "pace with the pen resting");

// small loops are a miss, not "too few loops to count"
const tiny = real({ height: 36 });
assert.ok(tiny.counted && !tiny.reachedTarget);
near(tiny.measures.size, 0.3, 0.03, "small loops' size");

// writing a little above the baseline: size is measured from the writing's own bottom
near(real({ floatPx: 25 }).measures.size, 1, 0.05, "size above the baseline");
// small loops written up near the line don't touch it
const perched = real({ height: 50, floatPx: 70 });
assert.ok(perched.counted && perched.measures.reached === 0 && !perched.reachedTarget);

// a row that shrinks along the line says so
assert.ok(real({ shrinkBy: 0.4 }).measures.shrink < -0.25);

// size and speed alone don't change smoothness; stop-start writing does
for (const opts of [{ height: 60 }, { height: 240 }, { loopSecs: 0.45 }, { loopSecs: 1.2 }]) {
  near(real(opts).measures.peaksPerLoop, plain.measures.peaksPerLoop, 0.25, `smoothness ${JSON.stringify(opts)}`);
}
const history = [plain.measures, real({ seed: 2 }).measures, real({ seed: 3 }).measures];
const jerky = real({ jerky: 0.6 }, history);
assert.ok(jerky.reachedTarget && jerky.shakier && !jerky.hit, JSON.stringify(jerky.vs));
// bigger at the same pace after smaller tries: a hit, the goal of the exercise
const bigger = real({ height: 160 }, history);
assert.ok(bigger.hit && !bigger.slower && !bigger.shakier, JSON.stringify(bigger.vs));
// bigger by slowing down: reaches the line but doesn't count
const slowBig = real({ height: 160, loopSecs: 1.1 }, history);
assert.ok(slowBig.reachedTarget && slowBig.slower && !slowBig.hit, JSON.stringify(slowBig.vs));

// --- steady tracing -----------------------------------------------------------
// following a path at a steady speed. offset: px off the path, sideways.
// warp: speed swings (0..1), cycles of them over the whole path - a real hand
// speeds up and slows down a few times a turn. secs: time to trace the whole path.
function follow(path, { secs = 6, offset = 0, upTo = 1, warp = 0.3, cycles = 9, hz = 240, start = 0 } = {}) {
  const samples = [];
  for (let t = 0; t <= secs * upTo; t += 1 / hz) {
    const u = t / secs, uw = u + warp * Math.sin(2 * Math.PI * cycles * u) / (2 * Math.PI * cycles);
    const [x, y] = pointAlong(path, (start + uw * (1 - start)) * path.length);
    samples.push({ t, x: x + offset, y: y + offset });
  }
  return samples;
}
const spiral = tracingPath(340, 340);
assert.ok(Math.abs(spiral.radius - 146) < 1e-9);
const onLine = scoreTracing(follow(spiral), [0], spiral);
assert.ok(onLine.counted && onLine.reachedTarget && onLine.hit, JSON.stringify(onLine.measures));
assert.equal(onLine.measures.cover, 1);
assert.ok(onLine.measures.accuracy < 0.01);
near(onLine.measures.pace, spiral.length / spiral.radius / 6, 0.05, "tracing pace");
// wandering ~10% of the radius off the guide is a miss
const wander = scoreTracing(follow(spiral, { offset: 11 }), [0], spiral);
assert.ok(wander.counted && !wander.reachedTarget, JSON.stringify(wander.measures));
// a third of the spiral is too short to judge
assert.equal(scoreTracing(follow(spiral, { upTo: 0.3 }), [0], spiral).counted, false);
// accurate but twice as slow as recent tries doesn't count
const traceHistory = [onLine.measures, onLine.measures, onLine.measures];
const slowTrace = scoreTracing(follow(spiral, { secs: 12 }), [0], spiral, traceHistory);
assert.ok(slowTrace.reachedTarget && slowTrace.slower && !slowTrace.hit, JSON.stringify(slowTrace.vs));
// accurate at the same pace but stop-start doesn't count either
const jerkyTrace = scoreTracing(follow(spiral, { warp: 0.7, cycles: 27 }), [0], spiral, traceHistory);
assert.ok(jerkyTrace.reachedTarget && jerkyTrace.shakier && !jerkyTrace.hit, JSON.stringify(jerkyTrace.vs));
assert.equal(TRACE_TURNS, 3);

// --- rhythm ------------------------------------------------------------------
const wave = rhythmPath(340, 226);
near(wave.beatLength * RHYTHM_BEATS, wave.length, 1e-6, "beats tile the wave");
// beat boundaries land on tops and bottoms
near(pointAlong(wave, wave.beatLength)[1], 226 / 2 - 0.3 * 226, 1, "beat 1 ends at a top");
const beatSec = 60 / 60;
const inStep = scoreRhythm(follow(wave, { secs: RHYTHM_BEATS * beatSec }), [0], wave, { beatSec, penOffset: 0 });
assert.ok(inStep.counted && inStep.reachedTarget && inStep.hit, JSON.stringify(inStep.measures));
assert.ok(inStep.measures.lag < 0.05 && Math.abs(inStep.measures.lead) < 0.05);
assert.equal(inStep.vs.pace, null);
// setting off a beat late and staying a beat behind is a miss
const late = scoreRhythm(follow(wave, { secs: RHYTHM_BEATS * beatSec }), [0], wave, { beatSec, penOffset: 1 });
assert.ok(late.counted && !late.reachedTarget, JSON.stringify(late.measures));
near(late.measures.lead, -1, 0.1, "a beat behind");
// rushing to the end in half the time is a miss too
const rushed = scoreRhythm(follow(wave, { secs: RHYTHM_BEATS * beatSec / 2 }), [0], wave, { beatSec, penOffset: 0 });
assert.ok(!rushed.reachedTarget && rushed.measures.lead > 1, JSON.stringify(rushed.measures));
// waiting on the start point through the count-in doesn't hurt
const waited = follow(wave, { secs: RHYTHM_BEATS * beatSec });
const resting = Array.from({ length: 240 }, (_, i) => ({ t: i / 240, x: waited[0].x, y: waited[0].y }));
const withRest = [...resting, ...waited.map((p) => ({ ...p, t: p.t + 1 }))];
assert.ok(scoreRhythm(withRest, [0], wave, { beatSec, penOffset: -1 }).hit);
// keeping up by speeding up and slowing down along the wave isn't shaky; a
// line that wobbles across the wave is
const shaken = (samples, px) => samples.map((p) => ({ ...p, y: p.y + px * Math.sin(2 * Math.PI * 5 * p.t) }));
const steadyBeat = scoreRhythm(shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec }), 1), [0], wave, { beatSec, penOffset: 0 });
const beatHistory = [steadyBeat.measures, steadyBeat.measures, steadyBeat.measures];
const surging = scoreRhythm(shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec, warp: 0.8, cycles: 24 }), 1), [0], wave, { beatSec, penOffset: 0 }, beatHistory);
assert.ok(surging.hit && !surging.shakier, JSON.stringify([surging.measures, surging.vs]));
assert.ok(surging.measures.peaksPerBeat > 1.5 * steadyBeat.measures.peaksPerBeat, "surges add speed peaks");
const wobbly = scoreRhythm(shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec }), 3), [0], wave, { beatSec, penOffset: 0 }, beatHistory);
assert.ok(wobbly.reachedTarget && wobbly.shakier && !wobbly.hit, JSON.stringify([wobbly.measures, wobbly.vs]));
// tries saved before wobble was measured are left out of the comparison
assert.equal(scoreRhythm(shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec }), 3), [0], wave, { beatSec, penOffset: 0 },
  [{ peaksPerBeat: 3 }, { peaksPerBeat: 3 }]).vs.smoothness, null);

// --- hand skills ---------------------------------------------------------------
assert.equal(targetRadius(96, 0), 48);
assert.equal(targetRadius(96, SHRINK_SECS / 2), 24);
assert.equal(targetRadius(96, SHRINK_SECS + 1), 0);
const all = Array.from({ length: TARGETS }, (_, i) => ({ caught: true, ms: 500 + i }));
const tapped = scoreTargets(all, 0);
assert.ok(tapped.counted && tapped.hit && tapped.measures.caught === TARGETS && tapped.measures.reactionMs === 507);
const some = all.map((r, i) => ({ ...r, caught: i % 3 !== 0 })); // 10 of 15
assert.ok(scoreTargets(some, 4).counted && !scoreTargets(some, 4).hit);
assert.ok(!scoreTargets(all.slice(0, 5), 0).counted);

// --- loopholes (found by hand on Oct 5) ---------------------------------------
// humps that reach the line but never close into a loop are attempts that miss
const humps = scoreBigWriting(loops({ closed: false }), [0], geo);
assert.ok(humps.counted && humps.measures.loops === 8 && humps.measures.reached === 0 && humps.measures.open === 8);
assert.ok(!humps.reachedTarget && humps.marks.every((m) => !m.reached));
assert.equal(plain.measures.open, 0);
// one spike in a row of loops is one miss, marked with a ring
function joinRows(...rows) {
  const samples = [], strokeStarts = [0];
  let dx = 0, dt = 0;
  for (const row of rows) {
    const x0 = row[0].x, t0 = row[0].t;
    for (const p of row) samples.push({ ...p, x: p.x - x0 + dx, t: p.t - t0 + dt });
    dx = samples.at(-1).x;
    dt = samples.at(-1).t + 1 / 240;
  }
  return { samples, strokeStarts };
}
const row = (n) => cursiveRow({ n, sizeVar: 0 }).samples;
const spiked = joinRows(row(4), loops({ n: 1, closed: false }), row(3));
const withSpike = scoreBigWriting(spiked.samples, spiked.strokeStarts, geo);
assert.equal(withSpike.measures.loops, 8);
assert.equal(withSpike.measures.reached, 7);
assert.equal(withSpike.measures.open, 1);
// small bumps between tall loops count as letters that fell short, not as nothing
const bumpy = joinRows(row(4), cursiveRow({ n: 2, height: 30, sizeVar: 0 }).samples, row(2));
const withBumps = scoreBigWriting(bumpy.samples, bumpy.strokeStarts, geo);
assert.equal(withBumps.measures.loops, 8, JSON.stringify(withBumps.measures));
assert.equal(withBumps.measures.reached, 6);
// a row that shrinks to tiny letters at the end keeps every letter
const fading = joinRows(row(5), cursiveRow({ n: 3, height: 25, sizeVar: 0 }).samples);
const shrunk = scoreBigWriting(fading.samples, fading.strokeStarts, geo);
assert.equal(shrunk.measures.loops, 8);
assert.ok(shrunk.measures.shrink < -0.5, `shrink ${shrunk.measures.shrink}`);
// a mouse reports whole pixels, so strokes often cross by sharing one: closed
// loops written with a mouse still count
const byMouse = mouseLike(cursiveRow({}));
assert.equal(scoreBigWriting(byMouse.samples, byMouse.strokeStarts, geo).measures.reached, 8);
// every letter shape, written with a pen and with a mouse: narrow l's, l's
// written back down over themselves and e's count; spikes, teeth, humps, n's
// and tents with a small curl on top don't
for (const [shape, { loop }] of Object.entries(SHAPES)) {
  for (const slant of [0, 0.3]) {
    const pen = letterRow(Array(8).fill(shape), { height: 132, slant });
    for (const [input, w] of [["pen", pen], ["mouse", mouseLike(pen)]]) {
      const m = scoreBigWriting(w.samples, w.strokeStarts, geo).measures;
      assert.equal(m.loops, 8, `${shape} ${input} slant ${slant}`);
      assert.equal(m.reached, loop ? 8 : 0, `${shape} ${input} slant ${slant}`);
      assert.equal(m.open, loop ? 0 : 8, `${shape} ${input} slant ${slant}`);
    }
  }
}
// loops that dip well below the baseline don't count, nor does the letter
// that starts from the bottom of one
const dipped = letterRow([...Array(3).fill({ shape: "closedL", drop: 60 }), ...Array(5).fill("closedL")], { height: 132 });
const withDips = scoreBigWriting(dipped.samples, dipped.strokeStarts, geo).measures;
assert.equal(withDips.loops, 8);
assert.equal(withDips.reached, 4);
assert.equal(withDips.below, 4);
// going up and down over the same spot is one letter, not a row
const inPlace = Array.from({ length: 400 }, (_, i) => ({ t: i / 120, x: 300 + 0.05 * i, y: 300 - 66 * (1 - Math.cos((2 * Math.PI * i) / 40)) }));
const scribble = scoreBigWriting(inPlace, [0], geo);
assert.equal(scribble.measures.loops, 1);
assert.ok(!scribble.counted && !scribble.hit);

// tapping everywhere isn't catching: 15 caught with 163 stray taps is a miss
assert.ok(!scoreTargets(all, 163).reachedTarget);
assert.ok(scoreTargets(all, 3).hit && !scoreTargets(all, 4).hit);

console.log("TRAIN OK");
