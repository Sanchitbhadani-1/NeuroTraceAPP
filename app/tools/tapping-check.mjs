import assert from "node:assert/strict";
import { analyzeTaps } from "../tapping.js";

const FPS = 30;

// Fingers start open; each cycle closes once (a tap) and opens again
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

// Steady
{
  const r = analyzeTaps({ samples: taps() });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.equal(r.counted, true);
  assert.equal(r.tapTimes.length, 10);
  assert.equal(r.openings.length, 10);
  near(r.rate, 2.5, 0.1, "rate");
  near(r.duration, 3.6, 0.07, "duration");
  assert.ok(r.rhythmCv < 0.05, `rhythmCv ${r.rhythmCv}`);
  near(r.openingChange, 0, 0.05, "openingChange");
  near(r.rateChange, 0, 0.05, "rateChange");
  near(r.meanOpening, 1.05, 0.06, "meanOpening");
  assert.equal(r.pauses, 0);
}

// Shrinking openings
{
  const r = analyzeTaps({ samples: taps({ amp: (p) => 1 - 0.4 * p }) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.ok(r.openingChange < -0.2, `openingChange ${r.openingChange}`);
  near(r.rateChange, 0, 0.05, "rateChange");
}

// Slowing down
{
  const r = analyzeTaps({ samples: taps({ hz: (p) => 3 - p }) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.ok(r.rateChange < -0.15, `rateChange ${r.rateChange}`);
  near(r.openingChange, 0, 0.05, "openingChange");
}

// One glitched frame while the hand is open
{
  const samples = taps().map((s, i) => (i === 36 ? { t: s.t, gap: 0.1 } : s));
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// Short holes are smoothed over
{
  const samples = taps().map((s, i) => (i % 7 === 3 ? { t: s.t, gap: null } : s));
  assert.equal(analyzeTaps({ samples }).taps, 10);
}

// Long hole is not bridged: hand lost while open, back already closed
{
  const valley = 5.5 / 2.5;
  const samples = taps().map((s) => (s.t > valley - 0.25 && s.t < valley - 0.02 ? { t: s.t, gap: null } : s));
  const r = analyzeTaps({ samples });
  noNaN(r);
  assert.equal(r.taps, 9);
}

// Pause
{
  const r = analyzeTaps({ samples: join(taps({ n: 5 }), hold(0.6, 1.1), taps({ n: 5 })) });
  noNaN(r);
  assert.equal(r.taps, 10);
  assert.equal(r.pauses, 1);
}

// Too few taps
{
  const r = analyzeTaps({ samples: taps({ n: 3 }) });
  noNaN(r);
  assert.equal(r.taps, 3);
  assert.equal(r.counted, false);
}

// No hand at all
for (const samples of [[], hold(2, null), hold(2, 0.5)]) {
  const r = analyzeTaps({ samples });
  noNaN(r);
  assert.equal(r.taps, 0);
  assert.equal(r.counted, false);
  assert.equal(r.rate, null);
  assert.deepEqual(r.tapTimes, []);
}

console.log("TAPPING OK");
