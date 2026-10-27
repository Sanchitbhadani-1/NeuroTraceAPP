// PARITY.MJS TESTS THAT NT-FEATURES.JS GIVES THE SAME FEATURES AS THE PYTHON FOR EVERY TRACE IN THE FIXTURE
// MAKE THE FIXTURE IN training/ WITH python parity/make_reference.py <uci_root> parity/reference.json
// RUN IT FROM THE REPO FOLDER WITH node app/tools/parity.mjs training/parity/reference.json

import fs from "node:fs";
import { featuresFromTrace, SPIRAL_FEATURE_ORDER } from "../core/nt-features.js";

// The biggest allowed difference, as a share of the Python value
// The features go from about 0.000001 to 100, and rounding differences land around this size
const TOL = 1e-9;

// Read the fixture from the path given, or from the normal place
const path = process.argv[2] ?? "training/parity/reference.json";
const ref = JSON.parse(fs.readFileSync(path, "utf8"));

// The biggest difference found for each feature, and the trace it came from
const worst = new Map();
for (const k of SPIRAL_FEATURE_ORDER) {
  worst.set(k, { rel: 0, case: "-" });
}

// Count the mismatches and the traces that ran
let failed = 0;
let ran = 0;

for (const c of ref.cases) {

  // Measure the trace in JavaScript, and count it as a mismatch if JavaScript fails where Python didn't
  let got;
  try {
    got = featuresFromTrace(c, ref.fs);
  } catch (e) {
    console.log(`FAIL ${c.name}: JS threw "${e.message}" but Python produced features`);
    failed++;
    continue;
  }
  ran++;

  for (const k of SPIRAL_FEATURE_ORDER) {
    const a = got[k];
    const b = c.features[k];

    // Both sides being NaN counts as a match
    if (Number.isNaN(a) && Number.isNaN(b)) {
      continue;
    }

    // Find the difference as a share of the Python value, without dividing by 0
    const rel = Math.abs(a - b) / Math.max(1e-12, Math.abs(b));

    // Keep track of the biggest difference for this feature
    const w = worst.get(k);
    if (rel > w.rel) {
      worst.set(k, { rel, case: c.name });
    }

    // Count a mismatch when the difference is too big, or when only one side is NaN
    if (!(rel <= TOL)) {
      console.log(`FAIL ${c.name} ${k}: js=${a} py=${b} rel=${rel.toExponential(2)}`);
      failed++;
    }
  }
}

// Print the biggest difference for each feature and the trace it came from
console.log(`\n${ran}/${ref.cases.length} traces ran. Worst relative difference per feature:\n`);
for (const k of SPIRAL_FEATURE_ORDER) {
  const w = worst.get(k);
  console.log(`  ${k.padEnd(28)} ${w.rel.toExponential(2).padStart(9)}   ${w.case}`);
}

// Say whether everything matched, and exit with 1 when anything failed
if (failed) {
  console.log(`\n${failed} MISMATCHES`);
  process.exit(1);
}
console.log(`\nPARITY OK - all ${ran} traces, all ${SPIRAL_FEATURE_ORDER.length} features within ${TOL}`);
process.exit(0);