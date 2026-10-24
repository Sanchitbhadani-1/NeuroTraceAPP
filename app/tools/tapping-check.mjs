import assert from "node:assert/strict";
import { analyzeTaps } from "../tapping.js";

const FPS = 30;

// Mulberry32, the same seeded random numbers as tools/handwriting.mjs, so a seed gives the same frames as the Swift test
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

// Made-up camera frames: fingers start open, close once per cycle (a tap). hz and amp take progress 0..1
function taps({ n = 10, hz = () => 2.5, amp = () => 1 } = {}) {
  const samples = [];
  let phase = 0;
  for (let i = 0; phase <= 2 * Math.PI * n; i++) {
    const p = phase / (2 * Math.PI * n);
    samples.push({ t: i / FPS, gap: 0.1 + amp(p) * (1 + Math.cos(phase)) / 2 });
    phase += 2 * Math.PI * hz(p) / FPS;
  }
  return samples;
}

function hold(seconds, gap) {
  return Array.from({ length: Math.round(seconds * FPS) }, (_, i) => ({ t: i / FPS, gap }));
}

function join(...parts) {
  const out = [];
  for (const part of parts) {
    const start = out.length ? out[out.length - 1].t + 1 / FPS : 0;
    for (const s of part) out.push({ t: start + s.t, gap: s.gap });
  }
  return out;
}

function noNaN(r) {
  for (const [key, value] of Object.entries(r)) {
    const values = Array.isArray(value) ? value : [value];
    for (const v of values) {
      if (typeof v === "number") assert.ok(Number.isFinite(v), `${key} is ${v}`);
    }
  }
}

const near = (a, b, tol, label) => assert.ok(Math.abs(a - b) <= tol, `${label}: ${a} not within ${tol} of ${b}`);

// Steady 2.5 taps/s: dips land at 0.2, 0.6, 1.0 s ...
{
  const r = analyzeTaps({ samples: taps() });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.equal(r.counted, true);
  assert.equal(r.tapTimes.length, 10);
  r.tapTimes.forEach((t, k) => near(t, 0.2 + 0.4 * k, 0.5 / FPS, `tap ${k} time`));
  assert.equal(r.openings.length, 10);
  near(r.rate, 2.5, 0.1, "rate");
  near(r.duration, 3.6, 0.07, "duration");
  assert.ok(r.rhythmCv < 0.05, `rhythmCv ${r.rhythmCv}`);
  near(r.openingChange, 0, 0.05, "openingChange");
  near(r.rateChange, 0, 0.05, "rateChange");
  near(r.meanOpening, 1.05, 0.06, "meanOpening");
  assert.equal(r.pauses, 0);
}

// Openings shrink to 60%: openingChange goes negative, speed stays put
{
  const r = analyzeTaps({ samples: taps({ amp: (p) => 1 - 0.4 * p }) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.ok(r.openingChange < -0.2, `openingChange ${r.openingChange}`);
  near(r.rateChange, 0, 0.05, "rateChange");
}

// Slows from 3 to 2 taps/s: rateChange goes negative, opening stays put
{
  const r = analyzeTaps({ samples: taps({ hz: (p) => 3 - p }) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.ok(r.rateChange < -0.15, `rateChange ${r.rateChange}`);
  near(r.openingChange, 0, 0.05, "openingChange");
}

// One frame reads "closed" mid-opening: smoothing keeps it from counting as a tap
{
  const samples = taps().map((s, i) => (i === 36 ? { t: s.t, gap: 0.1 } : s));
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// One wild frame (gap 4) plus smaller late taps: TRIM keeps those taps counted
{
  const samples = taps({ amp: (p) => (p < 0.5 ? 1 : 0.55) }).map((s, i) => (i === 20 ? { t: s.t, gap: 4 } : s));
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// Single missing frames are joined over, no taps lost
{
  const samples = taps().map((s, i) => (i % 7 === 3 ? { t: s.t, gap: null } : s));
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// Hand vanishes open and returns closed after > MAX_HOLE: no tap is guessed
{
  const valley = 5.5 / 2.5;
  const samples = taps().map((s) => (s.t > valley - 0.25 && s.t < valley - 0.02 ? { t: s.t, gap: null } : s));
  const r = analyzeTaps({ samples });
  noNaN(r);
  assert.equal(r.taps, 9);
}

// A 0.6 s hold mid-test is one pause
{
  const r = analyzeTaps({ samples: join(taps({ n: 5 }), hold(0.6, 1.1), taps({ n: 5 })) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.equal(r.pauses, 1);
}

// 3 taps: numbers still come back, but counted is false
{
  const r = analyzeTaps({ samples: taps({ n: 3 }) });
  noNaN(r);
  assert.equal(r.taps, 3);
  assert.equal(r.counted, false);
}

// A still hand whose reading jitters a little has no taps, however the noise falls
for (let seed = 1; seed <= 20; seed++) {
  const rand = rng(seed);
  const still = Array.from({ length: 300 }, (_, i) => ({ t: i / FPS, gap: 0.6 + (rand() - 0.5) * 0.16 }));
  assert.equal(analyzeTaps({ samples: still }).taps, 0, `still hand ${seed}`);
}
// Small taps that still open well past the jitter are counted
assert.equal(analyzeTaps({ samples: taps({ amp: () => 0.35 }) }).taps, 10);

// No input, no hand, or a hand that never moves: zero taps, nulls, no NaN
for (const input of [{}, { samples: [] }, { samples: hold(2, null) }, { samples: hold(2, 0.5) }]) {
  const r = analyzeTaps(input);
  noNaN(r);
  assert.equal(r.taps, 0);
  assert.equal(r.counted, false);
  assert.equal(r.rate, null);
  assert.deepEqual(r.tapTimes, []);
}

console.log("TAPPING OK");
