// TRAIN-CHECK.MJS TESTS TRAIN.JS ON MADE UP DRAWINGS WITH KNOWN ANSWERS
// IT CHECKS THE LEVEL RULE, THE SCORING OF ALL FOUR EXERCISES AND LOOPHOLES FOUND BY HAND
// RUN IT FROM THE REPO FOLDER WITH node app/tools/train-check.mjs

import assert from "node:assert/strict";
import {
  applyTry, tooHard, newLevelState, findLoops, scoreBigWriting, compareRecent,
  HITS_TO_LEVEL_UP, MISSES_TO_LEVEL_DOWN, EXERCISES,
  tracingPath, scoreTracing, rhythmPath, scoreRhythm, pointAlong, scoreTargets, targetRadius,
  TRACE_TURNS, RHYTHM_BEATS, TARGETS, SHRINK_SECS,
} from "../train.js";
import { cursiveRow, letterRow, mouseLike, SHAPES } from "./handwriting.mjs";


// How many levels big writing has
const LEVELS = EXERCISES["big-writing"].levels.length;

// A try that hit, a try that missed, and a try that was too short to count
const hit = { counted: true, hit: true };
const miss = { counted: true, hit: false };
const skip = { counted: false, hit: false };


// Apply a list of tries one after another and give back the level state at the end
function run(state, tries) {
  let current = state;
  for (const t of tries) {
    current = applyTry(current, t, LEVELS).state;
  }
  return current;
}


// Check that a number is within tol of what it should be
function near(a, b, tol, what) {
  assert.ok(Math.abs(a - b) <= tol, `${what}: ${a} vs ${b}`);
}


// THE LEVEL RULE

// It takes 3 hits to move up and 3 misses in a row to move down
assert.equal(HITS_TO_LEVEL_UP, 3);
assert.equal(MISSES_TO_LEVEL_DOWN, 3);

// Two hits keep the level, and the third hit moves up a level
let s = run(newLevelState(), [hit, hit]);
assert.deepEqual(s, { level: 0, hits: 2, misses: 0, last: null });
let r = applyTry(s, hit, LEVELS);
assert.equal(r.change, "up");
assert.deepEqual(r.state, { level: 1, hits: 0, misses: 0, last: "up" });

// Hits don't have to be in a row, misses do
s = run({ level: 1, hits: 0, misses: 0, last: null }, [miss, miss, hit]);
assert.deepEqual(s, { level: 1, hits: 1, misses: 0, last: null });
r = applyTry(run({ level: 1, hits: 1, misses: 0, last: null }, [miss, miss]), miss, LEVELS);
assert.equal(r.change, "down");
assert.deepEqual(r.state, { level: 0, hits: 0, misses: 0, last: "down" });

// Never below Level 1 or above the top level
s = run(newLevelState(), [miss, miss, miss, miss]);
assert.equal(s.level, 0);
s = run({ level: LEVELS - 1, hits: 0, misses: 0, last: null }, [hit, hit, hit, hit]);
assert.equal(s.level, LEVELS - 1);

// A try that didn't count changes nothing
const before = { level: 2, hits: 1, misses: 2, last: null };
assert.deepEqual(applyTry(before, skip, LEVELS).state, { level: 2, hits: 1, misses: 2, last: null });

// Too hard today drops one level and resets the counts, Level 1 stays
assert.deepEqual(tooHard({ level: 3, hits: 2, misses: 1, last: "up" }), { level: 2, hits: 0, misses: 0, last: "down" });
assert.deepEqual(tooHard(newLevelState()), newLevelState());


// BIG WRITING ON MADE UP LOOPS

// Make a row of n loops on a baseline at y = 300, each height px tall and secs seconds long, sampled at 120 Hz
// A wobble adds a fast shake, and closed: false draws humps that go straight back down
function loops({ n = 8, height = 120, secs = 0.8, wobble = 0, closed = true }) {
  const samples = [];
  const dt = 1 / 120;
  const total = n * secs;

  // How far each loop curls back, 0 for humps
  let back = 0;
  if (closed) {
    back = (1.7 * 600) / n / (2 * Math.PI);
  }

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

// The baseline and the target line height used for every big writing try
const geo = { baselineY: 300, targetPx: 120 };

// All 8 loops are found, each about 120 px tall
const tops = [];
for (const l of findLoops(loops({}), 300, 120)) {
  tops.push(l.own);
}
assert.equal(tops.length, 8);
for (const h of tops) {
  assert.ok(Math.abs(h - 120) < 2, `loop top ${h}`);
}

// Reaching the line with nothing to compare against is a hit on the target alone
const tall = scoreBigWriting(loops({}), [0], geo);
assert.ok(tall.counted && tall.reachedTarget && tall.hit, JSON.stringify(tall));
assert.equal(tall.measures.reached, 8);
assert.ok(Math.abs(tall.measures.pace - 1.25) < 0.05, `pace ${tall.measures.pace}`);
const peaks = tall.measures.peaksPerLoop;
assert.ok(peaks >= 1.5 && peaks <= 2.5, `peaks/loop ${peaks}`);
assert.equal(compareRecent(tall.measures, []).pace, null);

// Half-height loops miss the line
const small = scoreBigWriting(loops({ height: 60 }), [0], geo);
assert.ok(small.counted && !small.reachedTarget && !small.hit);
assert.equal(small.measures.reached, 0);

// Three loops is too short to judge
assert.equal(scoreBigWriting(loops({ n: 3 }), [0], geo).counted, false);

// Tall loops at half the recent pace are a miss
const recent = [tall.measures, tall.measures, tall.measures];
const slow = scoreBigWriting(loops({ secs: 1.6 }), [0], geo, recent);
assert.ok(slow.reachedTarget && slow.slower && !slow.hit, JSON.stringify(slow.vs));
assert.ok(Math.abs(slow.vs.pace + 0.5) < 0.05);

// Shaky loops at the same pace are a miss
const shaky = scoreBigWriting(loops({ wobble: 6 }), [0], geo, recent);
assert.ok(shaky.reachedTarget && shaky.shakier && !shaky.hit, JSON.stringify(shaky.vs));

// The same try again compares as unchanged
const same = scoreBigWriting(loops({}), [0], geo, recent);
assert.ok(same.hit && Math.abs(same.vs.pace) < 0.01 && Math.abs(same.vs.smoothness) < 0.01);

// Loops shrinking along the row give a negative shrink
const nine = loops({ n: 9 });
const lastT = nine.at(-1).t;
const shrinking = [];
for (const p of nine) {
  shrinking.push({ ...p, y: 300 - (300 - p.y) * (1 - 0.4 * (p.t / lastT)) });
}
assert.ok(scoreBigWriting(shrinking, [0], geo).measures.shrink < -0.2);


// BIG WRITING ON REALISTIC HANDWRITING FROM HANDWRITING.MJS

// Score a cursiveRow from handwriting.mjs, a row of slanted cursive l's sampled like an Apple Pencil
function real(opts, recent = []) {
  const { samples, strokeStarts } = cursiveRow(opts);
  return scoreBigWriting(samples, strokeStarts, geo, recent);
}

// A normal row has 8 loops at the right size and pace, and all 8 marks reach the line
const plain = real({});
assert.equal(plain.measures.loops, 8);
near(plain.measures.size, 1, 0.05, "size");
near(plain.measures.pace, 1 / 0.7, 0.05, "pace");
assert.ok(plain.hit);
assert.equal(plain.marks.length, 8);
for (const m of plain.marks) {
  assert.ok(m.reached && Number.isFinite(m.x) && Number.isFinite(m.y));
}

// Finds every loop across the tested sizes, speeds, slants, pen lifts and sampling rates
const rowOptions = [
  { height: 240 }, { height: 60 }, { height: 36 },
  { loopSecs: 0.45 }, { loopSecs: 1.2 },
  { slant: 0 }, { slant: 0.6 },
  { liftEvery: 3 }, { liftEvery: 1 },
  { jitter: 1.5 }, { n: 12 }, { hz: 60 }, { seed: 2 }, { seed: 3 },
];
for (const opts of rowOptions) {
  assert.equal(real(opts).measures.loops, opts.n ?? 8, JSON.stringify(opts));
}

// Resting the Pencil for a second before and after isn't slow writing
near(real({ rest: 1 }).measures.pace, 1 / 0.7, 0.05, "pace with the pen resting");

// Small loops are a miss, not too few loops to count
const tiny = real({ height: 36 });
assert.ok(tiny.counted && !tiny.reachedTarget);
near(tiny.measures.size, 0.3, 0.03, "small loops' size");

// When writing a little above the baseline, size is measured from the writing's own bottom
near(real({ floatPx: 25 }).measures.size, 1, 0.05, "size above the baseline");

// Small loops written up near the line don't touch it
const perched = real({ height: 50, floatPx: 70 });
assert.ok(perched.counted && perched.measures.reached === 0 && !perched.reachedTarget);

// A row that shrinks along the line gets a negative shrink
assert.ok(real({ shrinkBy: 0.4 }).measures.shrink < -0.25);

// Size and speed alone don't change smoothness
const smoothOptions = [{ height: 60 }, { height: 240 }, { loopSecs: 0.45 }, { loopSecs: 1.2 }];
for (const opts of smoothOptions) {
  near(real(opts).measures.peaksPerLoop, plain.measures.peaksPerLoop, 0.25, `smoothness ${JSON.stringify(opts)}`);
}

// Three normal tries to compare the next ones against
const history = [plain.measures, real({ seed: 2 }).measures, real({ seed: 3 }).measures];

// Stop-start writing is shakier
const jerky = real({ jerky: 0.6 }, history);
assert.ok(jerky.reachedTarget && jerky.shakier && !jerky.hit, JSON.stringify(jerky.vs));

// Bigger at the same pace after smaller tries is a hit
const bigger = real({ height: 160 }, history);
assert.ok(bigger.hit && !bigger.slower && !bigger.shakier, JSON.stringify(bigger.vs));

// Bigger loops at a slower pace are a miss
const slowBig = real({ height: 160, loopSecs: 1.1 }, history);
assert.ok(slowBig.reachedTarget && slowBig.slower && !slowBig.hit, JSON.stringify(slowBig.vs));


// STEADY TRACING

// Samples a path with position offsets and speed changes
function follow(path, { secs = 6, offset = 0, upTo = 1, warp = 0.3, cycles = 9, hz = 240, start = 0 } = {}) {
  const samples = [];
  for (let t = 0; t <= secs * upTo; t += 1 / hz) {
    const u = t / secs;
    const uw = u + warp * Math.sin(2 * Math.PI * cycles * u) / (2 * Math.PI * cycles);
    const [x, y] = pointAlong(path, (start + uw * (1 - start)) * path.length);
    samples.push({ t, x: x + offset, y: y + offset });
  }
  return samples;
}

// The spiral has 3 turns and a 146 px radius on a 340 by 340 pad
const spiral = tracingPath(340, 340);
assert.equal(TRACE_TURNS, 3);
assert.ok(Math.abs(spiral.radius - 146) < 1e-9);

// Tracing right on the spiral is a hit
const onLine = scoreTracing(follow(spiral), [0], spiral);
assert.ok(onLine.counted && onLine.reachedTarget && onLine.hit, JSON.stringify(onLine.measures));
assert.equal(onLine.measures.cover, 1);
assert.ok(onLine.measures.accuracy < 0.01);
near(onLine.measures.pace, spiral.length / spiral.radius / 6, 0.05, "tracing pace");

// Wandering about 10% of the radius off the guide is a miss
const wander = scoreTracing(follow(spiral, { offset: 11 }), [0], spiral);
assert.ok(wander.counted && !wander.reachedTarget, JSON.stringify(wander.measures));

// A third of the spiral is too short to judge
assert.equal(scoreTracing(follow(spiral, { upTo: 0.3 }), [0], spiral).counted, false);

// Accurate tracing at half the recent pace is a miss
const traceHistory = [onLine.measures, onLine.measures, onLine.measures];
const slowTrace = scoreTracing(follow(spiral, { secs: 12 }), [0], spiral, traceHistory);
assert.ok(slowTrace.reachedTarget && slowTrace.slower && !slowTrace.hit, JSON.stringify(slowTrace.vs));

// Accurate tracing with stop-start motion is a miss
const jerkyTrace = scoreTracing(follow(spiral, { warp: 0.7, cycles: 27 }), [0], spiral, traceHistory);
assert.ok(jerkyTrace.reachedTarget && jerkyTrace.shakier && !jerkyTrace.hit, JSON.stringify(jerkyTrace.vs));


// RHYTHM

// The beats cover the whole wave, and beat boundaries land on tops and bottoms
const wave = rhythmPath(340, 226);
near(wave.beatLength * RHYTHM_BEATS, wave.length, 1e-6, "beats tile the wave");
near(pointAlong(wave, wave.beatLength)[1], 226 / 2 - 0.3 * 226, 1, "beat 1 ends at a top");

// One beat a second
const beatSec = 60 / 60;

// Following the wave in step with the beat is a hit, and pace isn't compared
const inStep = scoreRhythm(follow(wave, { secs: RHYTHM_BEATS * beatSec }), [0], wave, { beatSec, penOffset: 0 });
assert.ok(inStep.counted && inStep.reachedTarget && inStep.hit, JSON.stringify(inStep.measures));
assert.ok(inStep.measures.lag < 0.05 && Math.abs(inStep.measures.lead) < 0.05);
assert.equal(inStep.vs.pace, null);

// Setting off a beat late and staying a beat behind is a miss
const late = scoreRhythm(follow(wave, { secs: RHYTHM_BEATS * beatSec }), [0], wave, { beatSec, penOffset: 1 });
assert.ok(late.counted && !late.reachedTarget, JSON.stringify(late.measures));
near(late.measures.lead, -1, 0.1, "a beat behind");

// Rushing to the end in half the time is a miss too
const rushed = scoreRhythm(follow(wave, { secs: RHYTHM_BEATS * beatSec / 2 }), [0], wave, { beatSec, penOffset: 0 });
assert.ok(!rushed.reachedTarget && rushed.measures.lead > 1, JSON.stringify(rushed.measures));

// Waiting on the start point through the lead-in doesn't hurt
const waited = follow(wave, { secs: RHYTHM_BEATS * beatSec });
const withRest = [];
for (let i = 0; i < 240; i++) {
  withRest.push({ t: i / 240, x: waited[0].x, y: waited[0].y });
}
for (const p of waited) {
  withRest.push({ ...p, t: p.t + 1 });
}
assert.ok(scoreRhythm(withRest, [0], wave, { beatSec, penOffset: -1 }).hit);


// Move every point up and down by px, 5 times a second
function shaken(samples, px) {
  const out = [];
  for (const p of samples) {
    out.push({ ...p, y: p.y + px * Math.sin(2 * Math.PI * 5 * p.t) });
  }
  return out;
}


// A steady line with a small shake, and three tries like it to compare against
const steadyLine = shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec }), 1);
const steadyBeat = scoreRhythm(steadyLine, [0], wave, { beatSec, penOffset: 0 });
const beatHistory = [steadyBeat.measures, steadyBeat.measures, steadyBeat.measures];

// Speeding up and slowing down along the wave isn't shaky, even though it adds speed peaks
const surgingLine = shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec, warp: 0.8, cycles: 24 }), 1);
const surging = scoreRhythm(surgingLine, [0], wave, { beatSec, penOffset: 0 }, beatHistory);
assert.ok(surging.hit && !surging.shakier, JSON.stringify([surging.measures, surging.vs]));
assert.ok(surging.measures.peaksPerBeat > 1.5 * steadyBeat.measures.peaksPerBeat, "surges add speed peaks");

// A line that wobbles across the wave is shakier
const wobblyLine = shaken(follow(wave, { secs: RHYTHM_BEATS * beatSec }), 3);
const wobbly = scoreRhythm(wobblyLine, [0], wave, { beatSec, penOffset: 0 }, beatHistory);
assert.ok(wobbly.reachedTarget && wobbly.shakier && !wobbly.hit, JSON.stringify([wobbly.measures, wobbly.vs]));

// Tries saved before wobble was measured are left out of the comparison
const oldTries = [{ peaksPerBeat: 3 }, { peaksPerBeat: 3 }];
assert.equal(scoreRhythm(wobblyLine, [0], wave, { beatSec, penOffset: 0 }, oldTries).vs.smoothness, null);


// HAND SKILLS

// A 96 px target starts with a 48 px radius, shrinks to 24 px halfway through, and is gone after SHRINK_SECS
assert.equal(targetRadius(96, 0), 48);
assert.equal(targetRadius(96, SHRINK_SECS / 2), 24);
assert.equal(targetRadius(96, SHRINK_SECS + 1), 0);

// Every target caught with no stray taps is a hit
const all = [];
for (let i = 0; i < TARGETS; i++) {
  all.push({ caught: true, ms: 500 + i });
}
const tapped = scoreTargets(all, 0);
assert.ok(tapped.counted && tapped.hit && tapped.measures.caught === TARGETS && tapped.measures.reactionMs === 507);

// 10 of 15 caught is a miss
const some = [];
for (let i = 0; i < all.length; i++) {
  some.push({ ...all[i], caught: i % 3 !== 0 });
}
assert.ok(scoreTargets(some, 4).counted && !scoreTargets(some, 4).hit);

// Only 5 targets is too few to count
assert.ok(!scoreTargets(all.slice(0, 5), 0).counted);


// LOOPHOLES FOUND BY HAND ON OCT 5

// Humps that reach the line but never close into a loop are attempts that miss
const humps = scoreBigWriting(loops({ closed: false }), [0], geo);
assert.ok(humps.counted && humps.measures.loops === 8 && humps.measures.reached === 0 && humps.measures.open === 8);
assert.ok(!humps.reachedTarget);
for (const m of humps.marks) {
  assert.ok(!m.reached);
}

// A normal row has no open loops
assert.equal(plain.measures.open, 0);


// Join rows of samples end to end into one stroke
function joinRows(...rows) {
  const samples = [];
  const strokeStarts = [0];
  let dx = 0;
  let dt = 0;
  for (const row of rows) {
    const x0 = row[0].x;
    const t0 = row[0].t;
    for (const p of row) {
      samples.push({ ...p, x: p.x - x0 + dx, t: p.t - t0 + dt });
    }

    // The next row starts where this one ended
    dx = samples.at(-1).x;
    dt = samples.at(-1).t + 1 / 240;
  }
  return { samples, strokeStarts };
}


// Make a row of n cursive l's that are all the same size
function row(n) {
  return cursiveRow({ n, sizeVar: 0 }).samples;
}


// One spike in a row of loops is one miss
const spiked = joinRows(row(4), loops({ n: 1, closed: false }), row(3));
const withSpike = scoreBigWriting(spiked.samples, spiked.strokeStarts, geo);
assert.equal(withSpike.measures.loops, 8);
assert.equal(withSpike.measures.reached, 7);
assert.equal(withSpike.measures.open, 1);

// Small bumps between tall loops count as letters that fell short
const bumpy = joinRows(row(4), cursiveRow({ n: 2, height: 30, sizeVar: 0 }).samples, row(2));
const withBumps = scoreBigWriting(bumpy.samples, bumpy.strokeStarts, geo);
assert.equal(withBumps.measures.loops, 8, JSON.stringify(withBumps.measures));
assert.equal(withBumps.measures.reached, 6);

// A row that shrinks to tiny letters at the end keeps every letter
const fading = joinRows(row(5), cursiveRow({ n: 3, height: 25, sizeVar: 0 }).samples);
const shrunk = scoreBigWriting(fading.samples, fading.strokeStarts, geo);
assert.equal(shrunk.measures.loops, 8);
assert.ok(shrunk.measures.shrink < -0.5, `shrink ${shrunk.measures.shrink}`);

// Closed loops written with a mouse still count
const byMouse = mouseLike(cursiveRow({}));
assert.equal(scoreBigWriting(byMouse.samples, byMouse.strokeStarts, geo).measures.reached, 8);

// Every letter shape, with a pen and a mouse, upright and slanted
// Narrow l's, written-over l's and e's count, and spikes, teeth, humps, n's and tents with a small curl don't
for (const [shape, { loop }] of Object.entries(SHAPES)) {
  for (const slant of [0, 0.3]) {
    const pen = letterRow(Array(8).fill(shape), { height: 132, slant });
    const inputs = [["pen", pen], ["mouse", mouseLike(pen)]];
    for (const [input, w] of inputs) {
      const m = scoreBigWriting(w.samples, w.strokeStarts, geo).measures;
      assert.equal(m.loops, 8, `${shape} ${input} slant ${slant}`);
      assert.equal(m.reached, loop ? 8 : 0, `${shape} ${input} slant ${slant}`);
      assert.equal(m.open, loop ? 0 : 8, `${shape} ${input} slant ${slant}`);
    }
  }
}

// Loops that dip well below the baseline don't count, nor does the letter starting from the bottom of one
const dippedLetters = [...Array(3).fill({ shape: "closedL", drop: 60 }), ...Array(5).fill("closedL")];
const dipped = letterRow(dippedLetters, { height: 132 });
const withDips = scoreBigWriting(dipped.samples, dipped.strokeStarts, geo).measures;
assert.equal(withDips.loops, 8);
assert.equal(withDips.reached, 4);
assert.equal(withDips.below, 4);

// Going up and down over the same spot is one letter, not a row
const inPlace = [];
for (let i = 0; i < 400; i++) {
  const y = 300 - 66 * (1 - Math.cos((2 * Math.PI * i) / 40));
  inPlace.push({ t: i / 120, x: 300 + 0.05 * i, y });
}
const scribble = scoreBigWriting(inPlace, [0], geo);
assert.equal(scribble.measures.loops, 1);
assert.ok(!scribble.counted && !scribble.hit);

// Tapping everywhere isn't catching, and 15 caught with 163 stray taps is a miss
assert.ok(!scoreTargets(all, 163).reachedTarget);

// 3 stray taps is still a hit, and 4 is a miss
assert.ok(scoreTargets(all, 3).hit && !scoreTargets(all, 4).hit);

console.log("TRAIN OK");