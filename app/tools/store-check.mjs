// Assert-based check for the pure parts of store.js that can run outside a
// browser (no IndexedDB in Node - those paths need real-browser testing).
// Not a framework - just the smallest thing that fails when the logic
// breaks. Run: node app/tools/store-check.mjs

import assert from "node:assert/strict";
import { newSubjectId, getPrefs, setPrefs } from "../store.js";

// --- newSubjectId: format ----------------------------------------------
for (let i = 0; i < 200; i++) {
  const id = newSubjectId(new Set());
  assert.match(id, /^[0-9a-f]{6}$/, `"${id}" is not 6 lowercase hex chars`);
}

// --- newSubjectId: retries until not in `existing` ----------------------
{
  const existing = new Set(["aaaaaa", "bbbbbb"]);
  for (let i = 0; i < 200; i++) {
    const id = newSubjectId(existing);
    assert.ok(!existing.has(id), `newSubjectId returned a collision: ${id}`);
  }
}

// --- newSubjectId: many calls stay unique against a growing set ---------
{
  const seen = new Set();
  for (let i = 0; i < 500; i++) {
    const id = newSubjectId(seen);
    assert.ok(!seen.has(id));
    seen.add(id);
  }
}

// --- getPrefs: defaults when localStorage is absent (Node has none) -----
assert.deepEqual(getPrefs(), { onboarded: false, consented: false, ageChoice: null, hand: "right" });

// --- setPrefs: never throws even with no localStorage to write to -------
assert.doesNotThrow(() => setPrefs({ onboarded: true }));

console.log("STORE OK");
