# Datasets — what we have, what we can use, and what is wrong with it

Written 13 Sept 2026, from measurements on the actual files, not from the papers.

## Summary

| Dataset | Status | Why |
|---|---|---|
| UCI 395 — *Parkinson Disease Spiral Drawings* | **Use, with care** | Real pen coordinates + timestamps. Has a serious acquisition confound (below). |
| UCI 358 — *Improved Spiral Test* | **Do not use** | Same subjects as UCI 395's `hw_dataset`. Several files are byte-identical. |
| NewHandPD (`HealthySignal` / `PatientSignal`) | **Cannot use** | Contains no pen coordinates at all. |
| PaHaW | **Needed** | The only balanced, single-session source we have. Licence-restricted (see below). |

---

## UCI 358 duplicates UCI 395

`data/improved+spiral+test+.../data/PWP/PWP (1).txt` and
`data/parkinson+disease+.../hw_dataset/parkinson/P_02100001.txt` have the same
MD5. The folder counts match too (15 healthy + 25 patients in both). 358 is a
re-release of the same 40 recordings.

Training on both would put the same person in the train fold and the test fold,
which inflates every score. **Use UCI 395 only.**

---

## NewHandPD has no coordinates

The `.txt` files under `HealthySignal/Signal` and `PatientSignal/Signal` have a
`#<meta>` header and then six tab-separated float columns sampled at 1000 Hz.
Measured ranges on `sigSp4-H7.txt`:

| col | min | max | what it is |
|---|---|---|---|
| 0 | 2.50 | 3.57 | microphone |
| 1 | 3.81 | 8.11 | finger grip |
| 2 | 5.30 | 9.20 | axial pressure of the ink refill |
| 3 | 5.02 | 6.81 | tilt / acceleration X |
| 4 | 3.64 | 5.05 | tilt / acceleration Y |
| 5 | 3.26 | 5.34 | tilt / acceleration Z |

All six are smart-pen (BiSP) voltages in the 2.5–9.2 V range. There is no x, no
y, and no timestamp column. Our entire pipeline is built on `(t, x, y)`, so
**nothing in NewHandPD can be fed to `preprocess_trace`.** There is no loader
for it in `neurotrace/datasets.py` and there should not be one.

(The other half of NewHandPD is scanned *images* of the drawings. Also no time
axis, so also unusable for tremor frequency.)

---

## UCI 395 — layout and format

```
hw_dataset/control/     15 files   healthy
hw_dataset/parkinson/   25 files   patients
new_dataset/parkinson/  37 files   patients, no controls
```

Semicolon CSV, no header, one row per sample:

```
X ; Y ; Z ; Pressure ; GripAngle ; Timestamp ; Test ID
213;205;0;15;1440;1351716;0
```

- `Timestamp` is **milliseconds** off an arbitrary clock. Only gaps are meaningful.
- `Z` is 0 in nearly every file. Ignored.
- Test ID `0` = static spiral (draw on the printed pattern), `1` = dynamic
  spiral (the pattern blinks), `2` = circles. **Only test 0 matches our app's
  task.** 1 and 2 are different movements and must never be pooled in.

Counts and quality for test 0:

- 76 of 77 files have a static spiral. `new_dataset/parkinson/H_p000-0017.txt`
  has test 2 only and is skipped automatically.
- Usable: **15 healthy, 61 patients.**
- Duration ranges 3.7 s to 103 s (median 18.2 s). Six are under 8 s and look
  like aborted attempts — they are kept, but `spiral_duration` is in the table
  so the sanity-check step can see them.
- **Sample rate is either 111.1 Hz or 142.9 Hz and varies by file.** Never
  hardcode it. `estimate_fs` reads it from the median gap.

---

## The confound — read this before quoting any number

Sample rate almost perfectly predicts the label:

| | healthy | patient |
|---|---|---|
| 142.9 Hz | 14 | 36 |
| 111.1 Hz | 1 | 25 |

Inside `hw_dataset` alone it is worse: **14 of 15 controls were recorded at
142.9 Hz and 25 of 25 patients at 111.1 Hz.** That is a recording-session
artifact — two groups recorded on different days or different tablet settings —
not a sign of disease. A classifier handed the raw sample rate would score about
0.98 and would have learned nothing about Parkinson's.

`preprocess_trace` resamples every trace onto a common 100 Hz grid before any
feature is computed, which is what stops the artifact from walking straight into
the model. This is no longer just a signal-quality argument for the resampler —
it is the thing keeping this dataset honest.

On top of that, `new_dataset` is patients only. Comparing it against
`hw_dataset`'s controls means comparing two different recording sessions.
**Train on `hw_dataset` only (15 vs 25).** `new_dataset` is fine as extra
patients for a patients-only check, never as the patient half of a comparison.

### What this does to the numbers

Single-feature AUC, all 76 vs `hw_dataset` only:

| feature | all 76 | hw only |
|---|---|---|
| spiral_tremor_4_6 | 0.828 | **0.696** |
| spiral_std_speed | 0.745 | 0.595 |
| spiral_ldlj | 0.675 | 0.509 |
| spiral_mean_speed | 0.646 | 0.437 |
| spiral_tremor_6_12 | 0.627 | 0.365 |
| spiral_std_distance | 0.614 | 0.544 |
| spiral_duration | 0.374 | 0.579 |
| spiral_radius_reversals | 0.299 | 0.453 |

Most of the apparent signal in the left column is the session artifact. The
right column is the honest one. **4–6 Hz band power at 0.70 on 40 subjects is
the real result** — and it is the Parkinsonian band, which is the mechanism we
predicted, not a number we went fishing for.

---

## Two features were broken on this data — both replaced 13 Sept

**Was `spiral_max/mean/std_distance`.** They measured the gap to
`reference_spiral()`, which is 3.76 turns counter-clockwise. UCI subjects traced
about **2.75 turns clockwise**, so the feature measured template mismatch and
scored 0.39–0.54.

Replaced by **`spiral_fit_residual`**, which builds the ideal spiral out of the
drawing itself. A spiral is just "radius grows in a straight line with angle",
so fitting a line through (θ, r) gives that person's own ideal spiral, and the
deviation from it is the wobble. Two extra columns, cos θ and sin θ, soak up a
wrong centre — without them a *perfect* spiral scores 0.048 instead of 0, and
that error moves with turn count, which is the old bug in a new costume. Four
columns, one least-squares solve; in JavaScript that is a 4×4 Gaussian
elimination, no optimizer. A Nelder-Mead search for the true centre scores the
same (0.864 vs 0.861) and is not worth the port.

Checked: four spirals of the same drawing quality but different turn counts and
directions now score within **1.12×** of each other. Against the old template
they varied by 1.65×. Keys renamed to `spiral_max/mean/std_deviation`.

**Was `spiral_radius_reversals`.** AUC 0.299 — it ran *backwards*, healthy 326
vs patients 231. It counted grid noise: a smooth slow radius on an integer grid
reads 10, 10, 11, 10, 11, 11, 12 … and every dip scored as a reversal.

Replaced by **`major_radius_reversals`**, which keeps a running extreme and only
counts a reversal once the radius pulls back from it by more than
`min_retrace = 0.10` (normalized units, so ~10% of the pen's distance from
centre). Grid jitter is ±1 unit and can never clear that; a real doubling-back
can. Swept the threshold from 0.01 to 0.30: a **broad plateau from 0.05 to 0.20
all scoring 0.80–0.86**, stable across quantization grids of 1, 2 and 4, p <
0.001 on 5000 label shuffles. Not one lucky threshold.

Honest caveat: at 0.10 this is no longer measuring 5 Hz tremor. It measures
gross doubling-back — hesitation and correction. Still a Parkinson's sign, which
is why it is not called "tremor" anything.

Other variants tested and rejected: an extra low-pass on the radius at 6, 8 and
12 Hz (0.46–0.51 — it removes the jitter and the signal together), and reversals
per second (0.31, worse than the raw count).

---

## Results after the fix

Patient-level 5-fold cross-validation, 30 repeats, `hw_dataset` only
(15 HC / 25 PD). Median [5th–95th percentile].

| feature set | model | AUC | balanced accuracy |
|---|---|---|---|
| all 12 | logistic regression | **0.933** [0.870–0.956] | **0.867** [0.806–0.900] |
| all 12 | gradient boosting | 0.904 [0.838–0.962] | 0.807 |
| 4 geometry only | logreg | 0.875 [0.852–0.888] | 0.763 |
| 3 tremor only | gboost | 0.713 [0.632–0.762] | 0.620 |

Before the fix the same run gave 0.784 / 0.720. Shuffling the labels 300 times
gives a median AUC of 0.505 and a 95th percentile of 0.680, against a real 0.936
— **p < 0.0001**.

Majority-class accuracy is 0.625, so quote balanced accuracy, never plain
accuracy.

### Proving the sample rate is not doing the work

`spiral_major_reversals` correlates 0.55 with `fs_raw`, which looks alarming
until you notice that in `hw_dataset` **`fs_raw` almost is the label**. Any
feature that predicts the label must correlate with it. Correlation cannot
separate the two here.

The test that can: take the 14 healthy controls recorded at 142.9 Hz, throw away
samples to fake 111.1 Hz, and re-extract. Same people, same drawings, only the
rate changed. If the features were reading the rate, the controls would drift
toward the patient means.

They move **0–1%** of the way. `spiral_ldlj` moves −9%, i.e. the wrong way.
`spiral_tremor_dominant_hz` moves 10%. Everything else is flat. The resampler is
doing its job and the result is not the confound.

(A weaker-looking test — comparing `hw_dataset` patients at 111 Hz against
`new_dataset` patients at 142.9 Hz — makes every feature look leaky. That test
is wrong: those are two different cohorts recorded years apart, so it cannot
tell "different rate" from "different patients". Do not use it.)

---

## PaHaW

Not in `data/`, and deliberately so. It is licence-restricted, obtained from a
private provider, and the agreement is between Sanchit and that provider — it
does not cover handing raw recordings to a third-party AI service.

**Rules:**

- The raw `.svc` files stay outside any folder shared with a third-party tool or service.
- Only Sanchit's own local scripts open them. `.gitignore` does not enforce this; folder placement does.
- Only derived, aggregate numbers leave the machine: feature tables, means, SDs,
  slopes, model scores. Never coordinate rows.
- The extraction script is written here and run by Sanchit locally; only the
  resulting table comes back.
- Re-read the signed licence for its terms on derived data and on what may
  appear in the video and the public repo.

`neurotrace/pahaw.py` is written and waiting. Its column order
(`y, x, t_ms, pen, azimuth, altitude, pressure` — **y first**) is from the
published description and has **not** been checked against the real files. Plot
one spiral before trusting a single distance feature; if x and y are swapped
every spiral is mirrored and nothing complains.

PaHaW matters more now than it did a week ago: 37 patients and 38 controls
recorded in one session is the only balanced source left after NewHandPD dropped
out and UCI turned out to be confounded.
