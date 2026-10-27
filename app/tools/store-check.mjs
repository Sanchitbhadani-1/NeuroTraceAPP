// STORE-CHECK.MJS TESTS THE PARTS OF STORE.JS THAT RUN WITHOUT A BROWSER
// IT CHECKS THE RANDOM IDS FOR RESEARCH PARTICIPANTS AND THE DEFAULT SETTINGS
// RUN IT FROM THE REPO FOLDER WITH node app/tools/store-check.mjs

import assert from "node:assert/strict";
import { newSubjectId, getPrefs, setPrefs } from "../old-website/store.js";

// Every new ID is 6 characters, each a number or a lowercase letter from a to f
for (let i = 0; i < 200; i++) {
  const id = newSubjectId(new Set());
  assert.match(id, /^[0-9a-f]{6}$/, `"${id}" is not 6 lowercase hex chars`);
}

// A new ID is never one that's already taken
const existing = new Set(["aaaaaa", "bbbbbb"]);
for (let i = 0; i < 200; i++) {
  const id = newSubjectId(existing);
  assert.ok(!existing.has(id), `newSubjectId returned a collision: ${id}`);
}

// 500 new IDs in a row never repeat
const seen = new Set();
for (let i = 0; i < 500; i++) {
  const id = newSubjectId(seen);
  assert.ok(!seen.has(id));
  seen.add(id);
}

// With nothing saved, the settings are the defaults
const defaults = {
  onboarded: false,
  consented: false,
  signedIn: false,
  ageChoice: null,
  hand: "right",
  theme: "auto",
  accent: "blue",
  motion: "auto",
};
assert.deepEqual(getPrefs(), defaults);

// Saving a setting doesn't crash when there's no browser storage, like in Node
assert.doesNotThrow(() => setPrefs({ onboarded: true }));

console.log("STORE OK");