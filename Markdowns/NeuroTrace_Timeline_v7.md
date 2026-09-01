# NeuroTrace — Timeline & Architecture (Web)

**Version 7 · August 30, 2026**

### How this fits with your other files

| File | Status |
|---|---|
| `NeuroTrace_ClaimsRules.md` | **Unchanged and still binding.** Platform-independent. Every claim still passes through it. |
| `NeuroTrace_RealWorldGaps.md` | **Unchanged.** The thirteen gaps and their wording don't care what the app is written in. |
| `NeuroTrace_Plan.md` (v5) | **Replaced by this file.** It assumes Swift, Xcode, TestFlight, and an eleven-week runway that no longer exists. Keep it only for Part One's feature descriptions and Part Four's future-expansions list. |

**Target submission:** Wednesday, October 21 · **Deadline:** Monday, October 26, 12:00 PM ET · **Buffer:** 5 days

---

## PART ONE — WHAT YOU'RE ACTUALLY BUILDING

A static website. HTML, CSS, JavaScript. No framework, no build step, no dependencies. It runs in Safari on an iPad, works with the Apple Pencil, and stores everything in the browser on that device.

Plus about twenty lines of Django on a separate host, for one optional feature.

### The three pieces and their real sizes

**Python — runs on a laptop, never at runtime.** Loads clinical datasets, computes features, trains and evaluates models, runs the experiments. On its final run it writes two small files and then it is done forever. It is a build-time tool, like a compiler.

**JavaScript — the entire app.** And here is the honest breakdown of where the work is:

| Portion of the JS | What it is |
|---|---|
| ~60% | **Feature extraction** — ported from Python. Resampling, filtering, SPARC, tremor band powers, spiral deviation, amplitude decline. This is the real work. |
| ~30% | Screens, canvas capture, IndexedDB storage, charts |
| ~10% | The exercises |
| ~1% | **The model.** Fifteen lines. |

The model is the smallest thing in the codebase. What Python hands you is a list of numbers, not logic.

**Django — one endpoint.** The opt-in contribution feature. Nothing else.

### What `model.json` actually contains

```json
{
  "featureOrder": ["spiral_sparc", "spiral_tremor_4_6", "hw_amplitude_decline_pct", "..."],
  "weights":      [-0.83, 1.24, -0.61, "..."],
  "intercept":    0.12,
  "featureMean":  [-1.94, 0.081, -12.4, "..."],
  "featureStd":   [0.42, 0.033, 9.1, "..."]
}
```

Five things, and the last two are the ones people forget. Training normalized every feature before fitting, so the app must normalize identically or the weights mean nothing.

A second file, `reference_percentiles.json`, holds coarse quantiles per feature for turning a measurement into a percentile. **Store deciles or 5-point steps, never raw per-participant values** — that matters for the PaHaW licence.

### Inference, in full

```js
function score(features) {
  let z = 0;
  for (let i = 0; i < M.featureOrder.length; i++) {
    const name = M.featureOrder[i];
    const norm = (features[name] - M.featureMean[i]) / M.featureStd[i];
    z += norm * M.weights[i];
  }
  z += M.intercept;
  return 1 / (1 + Math.exp(-z));   // computed, never displayed
}
```

That's the whole "AI" at runtime. Everything intelligent about it was decided in September by Python.

### Hosting

Static site on Netlify, Vercel, or GitHub Pages. Django on Railway, Render, or Fly.

**Keep them separate.** If Django serves the HTML, a server outage takes the app down and the one-directional design is undone. Django owns exactly one POST endpoint and nothing else.

---

## PART TWO — SEVEN AND A HALF WEEKS

Two tracks in parallel. **A** = Python, data, models (Sanchit). **B** = the app (Aryan). They converge in week 3.

### Week 1 · Aug 31 – Sep 6 — Foundations

**Both, before writing anything:** agree the trace JSON format and write it in a file. Both sides must read the same shape. Thirty minutes now saves days in week 3.

```json
{ "task": "spiral", "hand": "right", "inputType": "pencil",
  "deviceLabel": "iPad Pro 11", "samples": [
    {"t": 0.0000, "x": 412.3, "y": 288.1, "pressure": 0.62,
     "tiltX": 12, "tiltY": -5}
  ]}
```

**A** — Python feature extraction. Clean, resample to uniform 100 Hz, normalize, low-pass at 15 Hz, then speed, jerk, SPARC, log dimensionless jerk, tremor band powers, spiral deviation, amplitude decline, tapping decrement. **Validate against synthetic signals with known answers** — inject 5.5 Hz tremor, confirm 5.5 Hz returns; generate handwriting shrinking 30%, confirm −30%. Download UCI 395, UCI 358, NewHandPD, PADS.

**B** — page skeleton, routing, the why-are-you-here onboarding, consent, age gate. Canvas capture with `getCoalescedEvents()`. Record a stroke, save it, replay it with a speed graph beneath.

**Done when:** A's features pass synthetic tests. B can draw a spiral on the iPad and replay it.

### Week 2 · Sep 7 – Sep 13 — Data and tasks

**A** — features over UCI 395 and NewHandPD. First models: logistic regression and gradient boosting, patient-level splits, repeated for ranges. Expect numbers below the published literature. That's correct, not a bug.

**B** — all four task screens capturing real data: spiral, repetitive writing, alternating tap (twice, once per hand), phone motion via `DeviceMotionEvent`. Motion needs an explicit permission request on iOS triggered by a user gesture, on a secure origin. Prove that early.

**Done when:** A has a results table with ranges. B has four tasks producing valid trace files.

### Week 3 · Sep 14 – Sep 20 — Freeze and port

**A** — PaHaW when it arrives: writing-task features, the amplitude-decline slope **with its sign preserved**. Degradation experiment across three fidelity tiers. PADS differential. Then **freeze the feature list and export `model.json`.**

That freeze is binding. Anything added after it must be written twice and verified twice.

**B** — port the feature code to JavaScript. Then the **parity test**: twenty recorded traces through both implementations, every feature matching within tolerance.

**⚠ TRIPWIRE** — if the freeze slips past Sep 20, cut the optimizer simulation and the PADS differential. They're the least load-bearing experiments.

**Done when:** parity test passes on twenty traces.

### Week 4 · Sep 21 – Sep 27 — Results

**Both** — load the model, normalize, score, look up percentiles. Build the results screen per the ClaimsRules register: three tiers named for what was measured, per-measure percentiles, strongest contributing signals, what-this-means and what-to-do blocks. **No probability displayed.** Add the raw-versus-filtered stroke view. Save to IndexedDB.

**Storage policy:** keep computed features forever (a few hundred bytes each), raw traces only for the most recent few assessments plus anything queued for contribution. A year of raw traces would be hundreds of megabytes.

**⚠ TRIPWIRE** — if a full assessment isn't producing a result screen by Sep 27, TRAIN drops to one exercise.

**Done when:** a complete assessment on the iPad produces a real result and appears in history.

### Week 5 · Sep 28 – Oct 4 — Training, part one

Three exercises, each with its difficulty knob built in as you go — retrofitting is painful, adding up front is nearly free:

| Deficit | Exercise | Knob |
|---|---|---|
| Writing shrinks across the line | Large-amplitude writing, visual size targets | Target size |
| Jerky, hesitant, stop-start | Rhythm-paced continuous tracing | Tempo |
| Trajectory wanders | Guided accuracy tracing, fading guides | Guide visibility |

Plus the routing rule sending an assessment result to the exercise addressing the largest measured deficit.

**A, in parallel:** the optimizer simulation — write the learned optimizer, run it against a simulated patient with a known tradeoff curve, plot convergence. **Label the figure "simulated."**

**Done when:** an assessment routes correctly and each exercise is completable at any difficulty.

### Week 6 · Oct 5 – Oct 11 — Training part two, history, contribution

**Before/after measurement** around each exercise, all four dimensions shown together.

**The multi-objective rule** — if size improves while smoothness or speed drops past threshold, hold difficulty and change the cue to target what regressed.

**Adaptive progression** — rolling window of the last three sessions, up if the target was met in at least two, down if missed in at least two, 5–10% increments, floor and ceiling. Plus the **"too hard today"** button: drops a level instantly, no penalty, no effect on progression state.

**PROGRESS** — history list, personal baseline after three assessments, trend charts, printable export, medication logging with its time-since-dose chart.

**Contribution** — consent screen and the Django endpoint. Opt-in, one-directional, fails silently, no identifiers.

Heaviest week in the plan. Plan for it.

**⚠ TRIPWIRE** — entering Oct 11 incomplete, cut in this order: trend charts → adaptive progression (keep the multi-objective rule) → medication logging → printable export.

**Done when:** an exercise produces a before/after that responds correctly to a regression; history renders; a test contribution lands in the database.

### Week 7 · Oct 12 – Oct 18 — Real people, and filming

Ten to twenty testers on their own devices, unassisted. **Target older adults first** — grandparents, neighbours, a senior centre. People with Parkinson's are a bonus, not a requirement.

Walk every tester through **Add to Home Screen.** It makes IndexedDB storage persistent and stops Safari evicting their history after a week of not opening it.

**Film during this week.** Real users on real devices is footage you cannot fake later, and shooting here means the final days are editing, not scrambling.

Then the accessibility pass: large targets, high contrast, generous timing, no precise gestures, readable at default text size. Your users are older adults with motor difficulty — every failure here is invisible to you by construction.

Budget the week for fixing what testing finds, not building.

**Done when:** ten or more people completed an assessment with no help, and you have usable footage.

### Final days · Oct 19 – Oct 21 — Ship

**Video, 1 to 3 minutes.** Must include both names, the app name, the purpose in one sentence, the audience, the tools used, and a functionality demo. That leaves roughly sixty seconds of freedom — spend it on **one** gap from RealWorldGaps, and make it gap 1, the amplitude-versus-fluency tradeoff.

Shape: problem in a sentence → app named → live spiral capture → tremor extracted and shown → multi-objective rule catching a tradeoff on screen → one honest limitation.

Run the script and the written submission line by line against `NeuroTrace_ClaimsRules.md` before sending.

**Submit Wednesday, October 21.**

---

## PART THREE — EXPERIMENTS

Unaffected by the platform change, and the part that differentiates the project.

| # | Experiment | Data | Priority |
|---|---|---|---|
| 1 | Parkinson's vs healthy | UCI 395 + NewHandPD + PaHaW | **Essential** |
| 2 | Hardware degradation across three fidelity tiers | UCI + PaHaW, degraded | **Essential** |
| 3 | The sequence effect — does the amplitude-decline slope separate the groups, and does its sign behave as predicted? | PaHaW's repeated *l*, *le*, *les* | **High** |
| 4 | Parkinson's vs essential tremor | PADS, 188 vs 44 | If time |
| 5 | Optimizer in simulation | none | If time |

Experiment 2 is likely your most original technical contribution and needs nothing from anyone.

---

## PART FOUR — RISK

| Risk | Response |
|---|---|
| PaHaW signature delayed by the school | Chase this week. Experiments 1 and 2 run without it; experiment 3 doesn't |
| Model accuracy is mediocre | That's a *result*. Report ranges; the degradation gradient becomes the story |
| No Parkinson's patients available | Older-adult testers, and say so plainly in the video |
| Safari clears a tester's history | Add to Home Screen, walked through with every tester |
| Django endpoint down during judging | By design, nothing breaks. The app never depends on it |
| A week is lost to school | Use the tripwires. Do not compress weeks 7 and the final days |

### Never cut

The three drawing tasks, the results screen, one TRAIN exercise with before/after and the multi-objective rule, at least one real user in the video, and the video itself.

---

## THE THREE THINGS THAT DECIDE THE OUTCOME

**Recruiting testers** — slowest item, nobody starts early enough. Start this week.

**The video** — what judges actually experience, and it's three minutes.

**The limitations section** — cheapest credibility available, and almost no competing submission will have one.
