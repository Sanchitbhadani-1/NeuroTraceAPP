// TAPPING-CHECK.MJS TESTS TAPPING.JS ON MADE UP CAMERA FRAMES
// IT CHECKS THE TAP COUNT, SPEED, RHYTHM, OPENING SIZE AND PAUSES, AND WHAT HAPPENS WHEN THE HAND IS MISSING OR STILL
// RUN IT FROM THE REPO FOLDER WITH node app/tools/tapping-check.mjs

import assert from "node:assert/strict";
import { analyzeTaps } from "../tapping.js";

// Camera frames per second
const FPS = 30;


// Make repeatable random numbers from a seed, using Mulberry32
// It's the same as in handwriting.mjs, and a seed gives the same frames as the Swift test
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


// Make made up camera frames of a finger tapping, with the fingers starting open and closing once per tap
// hz is the taps per second and amp is how wide the fingers open
// Both are given how far through the taps the frame is, from 0 at the start to 1 at the end
function taps({ n = 10, hz = () => 2.5, amp = () => 1 } = {}) {
  const samples = [];
  let phase = 0;
  for (let i = 0; phase <= 2 * Math.PI * n; i++) {

    // How far through the taps this frame is
    const p = phase / (2 * Math.PI * n);

    // The gap between the fingers, 0.1 when closed and 0.1 plus amp when open
    const gap = 0.1 + amp(p) * (1 + Math.cos(phase)) / 2;
    samples.push({ t: i / FPS, gap });

    // Move on by one frame at this tap speed
    phase += 2 * Math.PI * hz(p) / FPS;
  }
  return samples;
}


// Make frames of a hand held still with the same gap for some seconds
function hold(seconds, gap) {
  const frames = [];
  const count = Math.round(seconds * FPS);
  for (let i = 0; i < count; i++) {
    frames.push({ t: i / FPS, gap });
  }
  return frames;
}


// Join groups of frames one after another
function join(...parts) {
  const out = [];
  for (const part of parts) {

    // Each group starts one frame after the last frame so far
    let start = 0;
    if (out.length) {
      start = out[out.length - 1].t + 1 / FPS;
    }

    for (const s of part) {
      out.push({ t: start + s.t, gap: s.gap });
    }
  }
  return out;
}


// Check that no number in the result is NaN or infinite, including numbers inside lists
function noNaN(r) {
  for (const [key, value] of Object.entries(r)) {
    let values = [value];
    if (Array.isArray(value)) {
      values = value;
    }

    for (const v of values) {
      if (typeof v === "number") {
        assert.ok(Number.isFinite(v), `${key} is ${v}`);
      }
    }
  }
}


// Check that a number is within tol of what it should be
function near(a, b, tol, label) {
  assert.ok(Math.abs(a - b) <= tol, `${label}: ${a} not within ${tol} of ${b}`);
}


// Steady taps at 2.5 a second, closing every 0.4 seconds from 0.2 seconds on
{
  const r = analyzeTaps({ samples: taps() });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.equal(r.counted, true);

  // Each tap is found at the right time
  assert.equal(r.tapTimes.length, 10);
  for (let k = 0; k < r.tapTimes.length; k++) {
    near(r.tapTimes[k], 0.2 + 0.4 * k, 0.5 / FPS, `tap ${k} time`);
  }
  assert.equal(r.openings.length, 10);

  // The speed, length, rhythm and opening size match, nothing shrinks or slows, and there are no pauses
  near(r.rate, 2.5, 0.1, "rate");
  near(r.duration, 3.6, 0.07, "duration");
  assert.ok(r.rhythmCv < 0.05, `rhythmCv ${r.rhythmCv}`);
  near(r.openingChange, 0, 0.05, "openingChange");
  near(r.rateChange, 0, 0.05, "rateChange");
  near(r.meanOpening, 1.05, 0.06, "meanOpening");
  assert.equal(r.pauses, 0);
}

// Openings that shrink to 60% give a negative opening change, and the speed stays the same
{
  const r = analyzeTaps({ samples: taps({ amp: (p) => 1 - 0.4 * p }) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.ok(r.openingChange < -0.2, `openingChange ${r.openingChange}`);
  near(r.rateChange, 0, 0.05, "rateChange");
}

// Slowing from 3 to 2 taps a second gives a negative speed change, and the opening stays the same
{
  const r = analyzeTaps({ samples: taps({ hz: (p) => 3 - p }) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.ok(r.rateChange < -0.15, `rateChange ${r.rateChange}`);
  near(r.openingChange, 0, 0.05, "openingChange");
}

// One frame that reads closed in the middle of an opening doesn't count as a tap
{
  const samples = taps();
  samples[36] = { t: samples[36].t, gap: 0.1 };
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// One wild frame doesn't stretch the range enough to lose the smaller taps later on
{
  const samples = taps({ amp: (p) => (p < 0.5 ? 1 : 0.55) });
  samples[20] = { t: samples[20].t, gap: 4 };
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// Single missing frames are joined over, and no taps are lost
{
  const samples = taps();
  for (let i = 0; i < samples.length; i++) {
    if (i % 7 === 3) {
      samples[i] = { t: samples[i].t, gap: null };
    }
  }
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// The hand leaves while open and comes back closed after more than MAX_HOLE, and no tap is guessed
{
  // The sixth closing is at 2.2 seconds
  const valley = 5.5 / 2.5;
  const samples = taps();
  for (let i = 0; i < samples.length; i++) {
    const t = samples[i].t;
    if (t > valley - 0.25 && t < valley - 0.02) {
      samples[i] = { t, gap: null };
    }
  }
  const r = analyzeTaps({ samples });
  noNaN(r);
  assert.equal(r.taps, 9);
}

// Holding still for 0.6 seconds in the middle counts as one pause
{
  const r = analyzeTaps({ samples: join(taps({ n: 5 }), hold(0.6, 1.1), taps({ n: 5 })) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.equal(r.pauses, 1);
}

// With only 3 taps the numbers still come back, but the test doesn't count
{
  const r = analyzeTaps({ samples: taps({ n: 3 }) });
  noNaN(r);
  assert.equal(r.taps, 3);
  assert.equal(r.counted, false);
}

// A still hand whose reading jitters a little has no taps, for 20 different random jitters
for (let seed = 1; seed <= 20; seed++) {
  const rand = rng(seed);
  const still = [];
  for (let i = 0; i < 300; i++) {
    still.push({ t: i / FPS, gap: 0.6 + (rand() - 0.5) * 0.16 });
  }
  assert.equal(analyzeTaps({ samples: still }).taps, 0, `still hand ${seed}`);
}

// Small taps that still open well past the jitter are counted
assert.equal(analyzeTaps({ samples: taps({ amp: () => 0.35 }) }).taps, 10);

// No input, no hand, or a hand that never moves gives zero taps, nulls and no NaN
const emptyInputs = [{}, { samples: [] }, { samples: hold(2, null) }, { samples: hold(2, 0.5) }];
for (const input of emptyInputs) {
  const r = analyzeTaps(input);
  noNaN(r);
  assert.equal(r.taps, 0);
  assert.equal(r.counted, false);
  assert.equal(r.rate, null);
  assert.deepEqual(r.tapTimes, []);
}

console.log("TAPPING OK");