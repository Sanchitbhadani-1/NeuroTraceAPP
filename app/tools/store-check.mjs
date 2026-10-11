import assert from "node:assert/strict";
import { newSubjectId, getPrefs, setPrefs } from "../store.js";

for (let i = 0; i < 200; i++) {
  const id = newSubjectId(new Set());
  assert.match(id, /^[0-9a-f]{6}$/, `"${id}" is not 6 lowercase hex chars`);
}

{
  const existing = new Set(["aaaaaa", "bbbbbb"]);
  for (let i = 0; i < 200; i++) {
    const id = newSubjectId(existing);
    assert.ok(!existing.has(id), `newSubjectId returned a collision: ${id}`);
  }
}

{
  const seen = new Set();
  for (let i = 0; i < 500; i++) {
    const id = newSubjectId(seen);
    assert.ok(!seen.has(id));
    seen.add(id);
  }
}

assert.deepEqual(getPrefs(), {
  onboarded: false, consented: false, signedIn: false, ageChoice: null,
  hand: "right", theme: "auto", accent: "blue", motion: "auto",
});
assert.doesNotThrow(() => setPrefs({ onboarded: true }));

console.log("STORE OK");
