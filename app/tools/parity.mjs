// Parity test: every trace in the fixture must give the same features in
// JavaScript as it does in Python.
//
//   python parity/make_reference.py <uci_root> parity/reference.json    (in training/)
//   node app/tools/parity.mjs training/parity/reference.json
//
// Tolerance is RELATIVE, because the features span 1e-6 (band power) to 1e2
// (duration). 1e-9 is roughly where float64 ordering differences land; a real
// port bug shows up orders of magnitude above it.

import fs from "node:fs";
import { featuresFromTrace, SPIRAL_FEATURE_ORDER } from "../nt-features.js";

const TOL = 1e-9;
const path = process.argv[2] ?? "training/parity/reference.json";
const ref = JSON.parse(fs.readFileSync(path, "utf8"));

const worst = new Map(SPIRAL_FEATURE_ORDER.map((k) => [k, { rel: 0, case: "-" }]));
let failed = 0, ran = 0;

for (const c of ref.cases) {
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
    const a = got[k], b = c.features[k];
    if (Number.isNaN(a) && Number.isNaN(b)) continue;
    const rel = Math.abs(a - b) / Math.max(1e-12, Math.abs(b));
    const w = worst.get(k);
    if (rel > w.rel) worst.set(k, { rel, case: c.name });
    if (!(rel <= TOL)) {
      console.log(`FAIL ${c.name} ${k}: js=${a} py=${b} rel=${rel.toExponential(2)}`);
      failed++;
    }
  }
}

console.log(`\n${ran}/${ref.cases.length} traces ran. Worst relative difference per feature:\n`);
for (const k of SPIRAL_FEATURE_ORDER) {
  const w = worst.get(k);
  console.log(`  ${k.padEnd(28)} ${w.rel.toExponential(2).padStart(9)}   ${w.case}`);
}
console.log(failed ? `\n${failed} MISMATCHES` : `\nPARITY OK - all ${ran} traces, all ${SPIRAL_FEATURE_ORDER.length} features within ${TOL}`);
process.exit(failed ? 1 : 0);
