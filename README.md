# NeuroTrace

A Parkinson's screening and monitoring web app for the Congressional App Challenge 2026 (GA-06, Rep. McBath). Submission deadline **Mon Oct 26, 12:00 PM ET**; internal target **Oct 21**.

Team: **Sanchit Bhadani** (Track A — Python, data, model) and **Aryan Modi** (Track B — the app, JavaScript, UI).

This README is the handoff document. It is written so that either of us can read it cold and know exactly where things stand, what the rules are, and what to do next. Last rewritten **Sept 18, 2026**. If you change something this file describes, change this file.

Supporting docs, read in this order if you're new:

1. this file
2. `markdowns/NeuroTrace_Timeline_v7.md` — the week-by-week plan and its tripwires
3. `markdowns/NeuroTrace_ClaimsRules.md` — what the app may and may not say to a user. **Binding.**
4. `docs/DATASETS.md` — what the training data actually is, measured, and what's wrong with it
5. `markdowns/NeuroTrace_RealWorldGaps.md` — the honest list of what this can't do

---

## 1. The idea, and why it's framed the way it is

A person draws a spiral on a phone or tablet. The app measures the drawing — tremor frequency, how far the pen wanders off a smooth spiral, how often it doubles back, how smooth the motion is — and compares those measurements against a reference sample. It reports **where the person sits relative to that sample**, per measure, in plain language. It does not diagnose. It never shows a probability.

The pitch, from research Sanchit did in Week 1 and will use in the video: Parkinson's is typically diagnosed **years after motor symptoms begin**, because early changes are subtle, gradual, and easy to attribute to age or stress. A person doesn't notice a 4% shrink in their handwriting per line. A measurement does. The app's value is not "detecting obvious tremor" — someone with obvious tremor already knows — it's surfacing small, consistent changes early enough to prompt a conversation with a doctor, and tracking them over time.

That framing is why the ClaimsRules doc exists and why it is binding. Everything the app shows is a measurement relative to a reference. Nothing it shows is a claim about disease.

---

## 2. How the system works

There are two halves and they connect through **one small file**.

```
  Python (training, offline, runs once)          JavaScript (the app, runs on every drawing)
  ───────────────────────────────────────         ──────────────────────────────────────────
  training/neurotrace/                            app/
    datasets.py   load real recordings              nt-signal.js    numpy-equivalents
    preprocess.py clean → trim → resample           nt-filters.js   scipy-equivalents
                  → normalize → low-pass            nt-features.js  same pipeline, same 12 numbers
    features.py   12 numbers per spiral
  training/scripts/                                app/app.js      capture, replay, (soon) score + results
    build_features.py  every recording → table
    evaluate.py        cross-validated AUC
    (todo) export_model.py ───────────────────►   app/model.json         weights, one per feature
                                              ►   app/percentiles.json   reference sample
```

**The Python never runs at runtime.** It runs on Sanchit's laptop, produces `model.json` and `percentiles.json`, and those two files ship with the app. Everything the user's device does is JavaScript.

That means the twelve numbers **must be computed identically on both sides**. The Python computes them to train the model; the JavaScript computes them to use it. If the two ever disagree, the model is fed numbers it was never trained on and its output is silently meaningless — no error, no crash, just wrong. The parity test (§5.4) exists to catch exactly that, and it is not optional.

---

## 3. Repo map

```
app/
  index.html, styles.css, app.js     capture screen, replay, speed graph (Aryan, Week 1)
  nt-signal.js                       interp, unwrap, gradient, arange, 4x4 solve, lstsq, FFT
  nt-filters.js                      Butterworth design, filtfilt, Welch  — matched to scipy to ~1e-15
  nt-features.js                     the pipeline; exports SPIRAL_FEATURE_ORDER and featuresFromTrace()
  tools/parity.mjs                   the parity test runner (node)
schema/
  trace.schema.json                  the recorded-trace shape. Both sides read it identically.
training/
  neurotrace/
    synth.py        fake spirals/writing/tapping with known tremor, plus degrade() for phone-quality data
    preprocess.py   clean, trim_stationary, resample_uniform, normalize, low_pass, preprocess_trace
    features.py     the 12 spiral features (+ writing and tapping extractors, not yet used)
    datasets.py     UCI 395 loader
    pahaw.py        PaHaW loader — written blind, UNVERIFIED against real files
    pen.py          reference_spiral() — draws the on-screen guide only; no longer used for scoring
  scripts/
    build_features.py   every recording → one CSV row
    evaluate.py         repeated patient-level cross-validation, honest ranges
  parity/
    make_reference.py   builds the parity fixture (30 traces + Python's answers)
    reference.json      the fixture — 6 MB, gitignored, regenerate in seconds
  results/
    features_uci395.csv the feature table. Aggregate numbers only; safe to commit.
  tests/                70 tests. `python -m pytest` from training/.
docs/
  DATASETS.md           the measured truth about the data
data/                   gitignored. UCI 395 + UCI 358 + NewHandPD live here. PaHaW does NOT.
markdowns/              timeline, claims rules, real-world gaps
```

---

## 4. Status — Sept 18

### Done

| | what | who |
|---|---|---|
| Week 1 | synthetic data generators, preprocessing, all 12 spiral features, writing + tapping extractors, 57 tests | Sanchit |
| Week 1 | capture screen (spiral), consent/age gate, replay, speed graph, trace schema | Aryan |
| Sept 8 | Aryan's parallel Python pipeline reconciled into Sanchit's — one implementation per feature (see §11) | Sanchit |
| Week 2 | datasets downloaded and inspected; two of three unusable (§6) | Sanchit |
| Week 2 | `datasets.py` — UCI 395 loader with per-file sample-rate detection, tests | Sanchit |
| Week 2 | feature table built, cross-validated: **0.784 AUC** with Week 1 features | Sanchit |
| Week 2 | two features found broken on real data, replaced (§7): **0.933 AUC, 0.867 balanced accuracy** | Sanchit |
| Week 3 | JavaScript port of the full spiral pipeline | Sanchit |
| Week 3 | parity test — 30 traces, 12 features, all agree within 1e-9 (most within 1e-13), **passing on Sanchit's machine** | Sanchit |

70 tests passing. Everything committed as of `36eb4f6`.

### Not done

- `model.json` and `percentiles.json` don't exist — the export script isn't written
- The app computes no features and shows no results — `nt-features.js` exists but nothing in `app.js` calls it
- No results screen
- No storage beyond one trace in `localStorage`
- PaHaW not loaded (§6.4)
- Feature list not formally frozen
- `docs/TRACE_FORMAT.md` not written
- Writing and tapping: extractors exist in Python, no capture screens, no JS port, no training data. **Out of scope for v1.**
- Testers not recruited

---

## 5. The contracts — things that must never silently diverge

There are four. Each one is a place where the Python side and the JavaScript side have to agree, and where disagreement produces no error.

### 5.1 The trace shape — `schema/trace.schema.json`

What the app records and what the Python reads. `{ task, hand, inputType, deviceLabel, samples: [{t, x, y, pressure?, tiltX?, tiltY?}] }`. `t` is seconds since the first sample of the trace. `x, y` are canvas pixels — units don't matter because `normalize` removes them, but **y grows downward** (screen convention) on both sides.

### 5.2 The preprocess order

```
clean → trim_stationary → resample_uniform(100 Hz) → normalize → low_pass(15 Hz)
```

In that order, with those parameters, on both sides. `preprocess_trace` in Python and `preprocessTrace` in JS. Each step's position matters and the comments in `preprocess.py` say why.

### 5.3 `featureOrder`

The twelve keys, in this order. `SPIRAL_FEATURE_ORDER` in `app/nt-features.js` is the single source of truth; `extract_spiral_features` in Python produces the same keys in the same order and a test pins it.

```
spiral_duration
spiral_max_deviation      spiral_mean_deviation     spiral_std_deviation
spiral_major_reversals
spiral_mean_speed         spiral_std_speed
spiral_ldlj               spiral_sparc
spiral_tremor_4_6         spiral_tremor_6_12        spiral_tremor_dominant_hz
```

`model.json` stores weights as a list in this order. If the order changes, the weights land on the wrong features and nothing complains. **Append only. Never rename, never reorder, never insert.** Dropping a feature after the freeze is fine — set its weight to zero, the JS still computes it, nothing breaks. Adding one costs two implementations and a parity run.

Four keys were renamed on Sept 13, before any freeze: `spiral_{max,mean,std}_distance → _deviation` and `spiral_radius_reversals → spiral_major_reversals`. Nothing downstream referenced the old names yet. That's the last rename.

### 5.4 The parity test

```
cd training
python parity/make_reference.py "../data/parkinson+disease+spiral+drawings+using+digitized+graphics+tablet" parity/reference.json
cd ..
node app/tools/parity.mjs training/parity/reference.json
```

Runs 30 traces — 20 synthetic across every fidelity tier, 10 real UCI recordings — through both pipelines and requires every feature to agree to one part in a billion. Takes about ten seconds. Current result: `PARITY OK`.

**Rule: anyone who edits `preprocess.py`, `features.py`, or any `app/nt-*.js` runs this before committing.** Not after, not "later." It already caught two bugs in the port that were invisible by inspection (§11).

---

## 6. What the data taught us — short version

Full detail with tables in `docs/DATASETS.md`. The headlines:

**6.1 Two of the three downloaded datasets are unusable.** NewHandPD's signal files are six smart-pen voltage channels — no x, no y. UCI 358 is a re-release of UCI 395's `hw_dataset`, same 40 people. **UCI 395 is the only usable one.**

**6.2 UCI 395 is confounded.** Inside `hw_dataset`, 14 of 15 healthy controls were recorded at 142.9 Hz and 25 of 25 patients at 111.1 Hz. Sample rate alone predicts the label at AUC 0.94. That's a recording-session artifact. `preprocess_trace`'s resample to a common 100 Hz grid is what stops it reaching the features — verified by faking the controls down to 111 Hz and watching the features move 0–1%. `new_dataset` has no controls at all, so it can't be used for comparison. **Train on `hw_dataset` only: 15 healthy, 25 patients.**

**6.3 The honest number is 0.933 AUC / 0.867 balanced accuracy** on those 40 people, patient-level 5-fold CV repeated 30 times, 5th–95th percentile 0.870–0.956. Shuffled labels give 0.50, best of 300 shuffles 0.68. Quote balanced accuracy, never plain accuracy (majority class is 62.5%). Quote the range, never the point.

**6.4 PaHaW is the dataset that matters** — 37 patients, 38 controls, one session, balanced. It is licence-restricted and Sanchit holds the licence. Rules that must survive into every session:

- Raw PaHaW files stay **outside** any folder shared with any third-party tool or service. `.gitignore` is not a boundary; folder placement is.
- Nothing but Sanchit's own local scripts ever opens them.
- Only aggregate numbers leave the machine: feature tables, means, model scores. Never coordinate rows.
- The extraction script runs on Sanchit's machine only, and only the resulting table leaves it.
- `pahaw.py` assumes column order `y, x, t_ms, pen, azimuth, altitude, pressure` (**y first**) from the published description. **Unverified.** Plot one spiral before trusting anything.

---

## 7. The twelve features, in plain terms

All computed on a preprocessed trace (normalized, so units are "fractions of the drawing's typical radius").

| feature | what it measures | why it matters |
|---|---|---|
| `spiral_duration` | seconds from first to last sample | slowness |
| `spiral_max/mean/std_deviation` | how far the pen sits off *this drawing's own* best-fit spiral | wander, wobble |
| `spiral_major_reversals` | how many times the pen pulls back inward by ≥10% of its radius | hesitation, correction |
| `spiral_mean/std_speed` | average pen speed and how much it varies | bradykinesia, stop-start |
| `spiral_ldlj` | log dimensionless jerk — one smoothness number | jerkiness |
| `spiral_sparc` | spectral arc length (Balasubramanian 2015) — another smoothness number | jerkiness, different lens |
| `spiral_tremor_4_6` | power in the 4–6 Hz band of the radius wobble | Parkinsonian tremor band |
| `spiral_tremor_6_12` | power in the 6–12 Hz band | essential tremor band |
| `spiral_tremor_dominant_hz` | the single strongest wobble frequency 3–12 Hz | which tremor, if any |

**Two of these were rebuilt on Sept 13 after real data broke them.** The deviation features used to measure distance to a *saved* template spiral; UCI subjects traced a different spiral (2.75 turns clockwise vs our 3.76 counter-clockwise), so the feature measured template mismatch and scored 0.39–0.54. Now it fits a spiral to the drawing itself — r = a + b·θ plus cos/sin terms to absorb a wrong centre — and measures deviation from that. Four spirals of the same quality but different shapes score within 1.12× of each other. `spiral_major_reversals` replaced a raw sign-flip count that was counting integer-grid jitter and ran *backwards* (healthy 326, patients 231). The deadband version only counts pull-backs bigger than ε; ε swept 0.01–0.30 shows a broad plateau 0.05–0.20 all at AUC 0.80–0.86, stable across quantization grids. Full reasoning in `docs/DATASETS.md`.

Standardized logistic-regression coefficients on hw_dataset, so you know what the model leans on: `major_reversals +0.93, tremor_6_12 −0.87, sparc −0.67, mean_deviation +0.60, std_deviation +0.57, mean_speed −0.43, max_deviation +0.36, duration +0.30, tremor_4_6 +0.29, std_speed +0.23, dominant_hz −0.12, ldlj +0.11`.

---

## 8. Track A — Sanchit — what's next, in order

**A1. Understand the Week 2 code.** `datasets.py`, the two feature fixes, `build_features.py`, `evaluate.py`. Same routine as Week 1: go function by function and rewrite the comments in his own words. This matters because Sanchit explains it in the video.

**A2. PaHaW.** Write `scripts/extract_pahaw.py` that reads the `.svc` files with `pahaw.py`, runs `preprocess_trace` + `extract_spiral_features` on the spiral task, and writes a feature CSV. Sanchit runs it locally. **First**: plot one PaHaW spiral and confirm x/y aren't swapped — if `pahaw.py`'s column order is wrong, every spiral is mirrored and the deviation features are garbage with no error. Then Sanchit sends the CSV back (aggregates only). Then re-run `evaluate.py` on hw_dataset + PaHaW. Expect the AUC to come *down* somewhat; that's the honest number.

**A3. Freeze.** Sanchit and Aryan agree the twelve keys above are final. Write the date into this file. From then on §5.3 applies with no exceptions.

**A4. `scripts/export_model.py`.** Trains the final logistic regression on all available labelled data (hw_dataset + PaHaW once loaded), writes `app/model.json` and `app/percentiles.json` in the exact shape §9.3 and §9.4 specify. Must:
- use `StandardScaler` and export its `mean_` and `scale_` — the JS has to standardize the same way
- use `class_weight="balanced"`
- store `featureOrder` verbatim from `SPIRAL_FEATURE_ORDER`
- store the training-set summary (n healthy, n patients, sources, date) inside the file so the app can say what its reference sample is
- refuse to write if `featureOrder` doesn't match what `extract_spiral_features` produces

**A5. Degradation experiment (Week 3 in the timeline).** Run the feature table through `degrade()` at all three tiers and report which features survive. Most of the data is already there from the quantization work: band power robust, jerk not, deadband stable. Turn it into one table for the video.

**A6. Docstrings.** Sanchit's, throughout.

**A7. Testers.** Non-code, slowest item in the plan. Start now.

Cut if time runs out (timeline tripwire): the optimizer simulation, the PADS differential.

---

## 9. Track B — Aryan — what's next, in order

**B0. Read this file and `markdowns/NeuroTrace_ClaimsRules.md`.**

**B1. Own the port.** Read `app/nt-signal.js`, `nt-filters.js`, `nt-features.js`, `tools/parity.mjs`. Run the parity test. Change anything you don't like — the test tells you if you broke it. Know that `filtfilt` and `welch` are matched to scipy's exact defaults and the awkward parts (odd-extension padding length, the steady-state initial condition, the periodic Hann window) are scipy's choices, not stylistic ones. `Math.max(...array)` is banned in these files — it overflows the stack on real traces. Use `maxOf`.

**B2. Wire features into the app.** After `endCapture`, call `featuresFromTrace(trace)` and, for now, `console.log` the result. This is the first time the app's own recorded format meets the pipeline — the parity test used Python-generated traces, so a mismatch between what `app.js` records and what `nt-features.js` expects would show up here and nowhere else. Things to check: `t` is in seconds not milliseconds; `t[0]` is 0; samples are in time order; there are enough of them (`lowPass` throws below ~50 samples, `spiralFitResidual` throws under one full turn — both are correct behaviour, the app needs to handle them with a "please draw the full spiral" message).

**B3. Load `model.json` and score — against a fake file.** The real file doesn't exist until A4. Write a fake `app/model.json` in the §9.3 shape with made-up numbers, write the loader and the scoring function, and get a (meaningless) score on screen. When the real file lands, nothing changes but the file. Scoring is:

```js
// features: the object featuresFromTrace returned
// model:    the parsed model.json
function score(features, model) {
  let z = model.bias;
  for (let i = 0; i < model.featureOrder.length; i++) {
    const raw = features[model.featureOrder[i]];
    const standardized = (raw - model.mean[i]) / model.scale[i];
    z += model.weights[i] * standardized;
  }
  return 1 / (1 + Math.exp(-z));   // 0..1 — internal only, NEVER shown
}
```

Iterate over `model.featureOrder`, never over a hand-typed list.

**B4. Percentiles — same trick, fake file first.** `percentiles.json` holds, for each feature and for the model score, the sorted values from the healthy reference sample. The app's lookup is: what fraction of the reference sample is below this user's value. That fraction is what the user sees. Handle `NaN` features (SPARC can return NaN on a very short trace) by omitting that measure from the display, not by crashing.

**B5. The results screen.** This is Week 4 and it's the biggest thing left. `ClaimsRules.md` specifies it and is binding:
- **No probability. Ever.** Not as a number, not as a bar, not as a colour ramp that secretly is one.
- Three tiers, **named for what was measured** ("several measures outside the typical range"), never for a condition. Proposed mechanism, to be confirmed against ClaimsRules: tier from where the model score falls among the healthy reference sample's scores — inside the middle 75% / in the top 20% / in the top 5%. Sanchit confirms the cutoffs.
- Per-measure percentiles, in plain words ("your 4–6 Hz tremor power is higher than 82% of our reference sample").
- Strongest contributing signals — the two or three features with the largest `weight × standardized value`.
- What-this-means and what-to-do blocks — text from ClaimsRules, not improvised.
- The raw-versus-filtered stroke overlay.
- State the reference sample honestly: "compared with N healthy adults recorded in [source]." That text comes from `model.json`'s training summary, not a hardcoded string.
Build it against fake numbers from B3/B4 now; swap real ones in later.

**B6. Storage.** IndexedDB. Keep computed features (and the score) forever — a few hundred bytes each. Keep raw traces only for the most recent few assessments plus anything queued for contribution. History screen reads the feature records.

**B7. `docs/TRACE_FORMAT.md` — with Sanchit, half an hour, before B2.** Contents: the on-screen spiral's turn count, direction, and start point (currently `TURNS = 4`, drawn centre-out; UCI's was ~2.75 clockwise — matching the training data is worth considering for the duration/speed features); the preprocess order; `featureOrder`; the "each sample is one tap" assumption for later. This document has been on the list since Week 1.

**Not Aryan's job for v1:** writing and tapping screens. No training data, not ported, model can't use them.

---

### 9.3 `model.json` — the exact shape

```json
{
  "version": 1,
  "task": "spiral",
  "featureOrder": ["spiral_duration", "...", "spiral_tremor_dominant_hz"],
  "mean":    [12 numbers — StandardScaler.mean_],
  "scale":   [12 numbers — StandardScaler.scale_],
  "weights": [12 numbers — LogisticRegression.coef_[0]],
  "bias":    -1.234,
  "trainedOn": {
    "date": "2026-09-XX",
    "sources": ["uci395:hw_dataset", "pahaw"],
    "nHealthy": 53,
    "nPatients": 62,
    "cvAuc": [0.87, 0.93, 0.96],
    "cvBalancedAccuracy": [0.81, 0.87, 0.90]
  }
}
```

`cvAuc` is `[5th percentile, median, 95th percentile]` — a range, never a point, per ClaimsRules. `featureOrder` must equal `SPIRAL_FEATURE_ORDER` exactly; the export script checks, and the app should check on load and refuse a mismatched file loudly.

### 9.4 `percentiles.json` — the exact shape

```json
{
  "version": 1,
  "reference": { "description": "healthy adults", "n": 53, "sources": ["uci395:hw_dataset", "pahaw"] },
  "features": {
    "spiral_tremor_4_6": [sorted ascending values from every healthy reference subject],
    "...": []
  },
  "score": [sorted ascending model scores from every healthy reference subject]
}
```

Percentile of a value v in a sorted list L = (count of L below v) / L.length. Keep the raw sorted values rather than pre-binned percentiles so the app can compute any cutoff without a rebuild.

---

## 10. Rules for everyone

1. **Run the parity test** before committing any change to `preprocess.py`, `features.py`, or `app/nt-*.js`. §5.4.
2. **`featureOrder` is append-only** once frozen. §5.3.
3. **Never display a probability.** Percentiles against a named reference sample. `ClaimsRules.md`.
4. **Report ranges, not points.** "0.87–0.96" not "0.93". `ClaimsRules.md`.
5. **PaHaW stays private.** §6.4. The folder boundary is what enforces it, not intent.
6. **One implementation per feature.** Nobody starts a parallel pipeline. If you think a feature is wrong, fix it in place and re-run parity.
7. **Commit as you go.** A week of work sat untracked once already.
8. **Sanchit writes his own comments and docstrings.** Any comment he hasn't rewritten yet is a placeholder.

---

## 11. Things that went wrong, so they don't again

**The duplicate pipeline (Sept 6–8).** Aryan's PR #1 shipped a second Python pipeline — `pipeline.py`, `signal.py`, `create_handwriting_synth`, `pen.spiral_deviation` — alongside Sanchit's. Two implementations of the same features means the JS port has two targets. Reconciled Sept 8: Aryan's versions were removed (git history keeps them), and his SPARC (the reference algorithm), Welch band-power approach, 2 Hz high-pass tremor residual, `features_from_trace` entry point, out-of-order-timestamp test, inf check, and short-trace guard were all kept and folded in. His `trace.schema.json` is untouched. **Aryan needs to hear this from Sanchit if he hasn't.**

**The bridge drop (Sept 13).** Six files — both feature fixes, updated tests, scripts, docs — were "delivered" but never reached disk because the connection to Sanchit's computer dropped mid-write. Nobody noticed for five days. Re-delivered Sept 18 and verified by running the tests on Sanchit's machine. Lesson: after any delivery, run the tests on the target machine.

**Two silent bugs in the JS port (Sept 18), both caught by parity.** (1) The backward pass of `filtfilt` was seeded with the first sample instead of the last — output looked like a perfectly good filtered spiral, error 5e-3. (2) `Math.max(...array)` overflowed the call stack on a long real recording. Neither would have been found by reading the code or looking at the output. The parity test found both in seconds. This is why rule 1 exists.

**A feature that separated the classes for the wrong reason.** The original `spiral_radius_reversals` gave AUC 0.30 on real data — strongly *inverted* — because it was counting integer-grid jitter, which healthy people produce more of. A model would have happily used it, and it would have failed on any device with a different grid. Lesson: a feature that separates the classes isn't automatically measuring what you think; check the direction and the mechanism.

---

## 12. Open decisions

- **Freeze date.** Sanchit + Aryan, together. After PaHaW is loaded is ideal; before is acceptable since dropping is free and adding is not.
- **On-screen spiral geometry.** Keep `TURNS = 4` or match the training data? Affects `duration` and speed features, not deviation. Goes in `TRACE_FORMAT.md`.
- **Tier cutoffs** for the results screen. Proposed 75/95 in B5; Sanchit confirms against ClaimsRules.
- **Whether writing/tapping make v1 at all.** Currently no. Revisit only if PaHaW's writing tasks load cleanly and there's slack after Week 4.
- **`spiral_major_reversals` ε.** 0.10 now, plateau is 0.05–0.20. Re-check on PaHaW before freezing.

---

## 13. Running things

```bash
# Python tests
cd training && python -m pytest

# Feature table from UCI
cd training && PYTHONPATH=. python scripts/build_features.py "../data/parkinson+disease+spiral+drawings+using+digitized+graphics+tablet" results/features_uci395.csv

# Honest cross-validation (hw_dataset only — the clean comparison)
cd training && PYTHONPATH=. python scripts/evaluate.py results/features_uci395.csv --release hw_dataset --repeats 30

# Parity
cd training && PYTHONPATH=. python parity/make_reference.py "../data/parkinson+disease+spiral+drawings+using+digitized+graphics+tablet" parity/reference.json
cd .. && node app/tools/parity.mjs training/parity/reference.json
```

`requirements.txt`: numpy, scipy, pandas, scikit-learn, matplotlib, pytest. Node 22 for the parity runner (the app itself needs no build step — plain ES modules).
