# Trace format

What `app/` records, what `training/` reads, and the order the two must agree on.
The shape itself is `schema/trace.schema.json`; this file covers the parts a
schema cannot state — the geometry on screen and the order of operations behind it.

Every constant below is quoted from the source. When one changes, change it
there and re-run `node app/tools/parity.mjs training/parity/reference.json`.

## The spiral on screen

`drawSpiralGuide()` in [app/app.js](../app/app.js) draws an Archimedean spiral
through `spiralPoints(0, maxR, TURNS, 1000)`:

- **Turns** — `TURNS = 4`.
- **Direction** — **centre-out**. Radius runs `0 → maxR` as the angle runs
  `0 → TURNS × 2π`, so the first point of the guide is the centre of the canvas
  and the last is the outermost edge. Increasing angle with the canvas's
  y-axis pointing down puts the drawn path clockwise on screen.
- **Start point** — the canvas centre, `(w/2, h/2)`. There is no separate start
  marker; the guide simply begins there.
- **Extent** — `maxR = min(w, h) / 2 - 20`, in CSS pixels.

The guide is a guide, not a constraint. Nothing snaps to it and nothing rejects
a stroke for wandering off it — the distance between the two is
`spiral_max_deviation` and the rest of the deviation family, which is the point.

## Sample units

`x` and `y` are CSS pixels in canvas space, measured from the canvas's top-left
corner, so `y` increases **downwards**. `t` is seconds since the first sample of
the stroke. Capture resolution is whatever the browser gives back from
`PointerEvent.getCoalescedEvents()`, which on most hardware is finer than one
sample per animation frame and is never uniform. Nothing downstream assumes it is.

**One sample is one tap.** Every sample carries the state of a single pointer
contact at one instant, and never an aggregate of several. Today's spiral is one
continuous stroke, so the distinction is invisible; it stops being invisible for
the writing and tapping tasks, where a trace holds many separate contacts. When
those land, they add samples to the same array under the same rule rather than
introducing a second, nested shape.

## Preprocess order

`preprocessTrace()` in [app/nt-features.js](../app/nt-features.js), mirroring
`training/neurotrace/preprocess.py` function for function. **The order is the
contract** — run these in a different sequence and the model sees numbers it was
never trained on:

1. **`clean`** — drop non-finite samples, and drop any sample whose timestamp is
   not greater than the largest timestamp kept so far.
2. **`trimStationary`** — cut the dead air at each end, where speed over a
   10-sample window is under `0.05 × median(speed)`. Pauses in the
   *middle* are kept; they are signal.
3. **`resampleUniform`** — linear interpolation onto a uniform **100 Hz** grid.
4. **`normalize`** — subtract the mean of x and y, then divide both by the RMS
   radius, so the trace is centred on the origin at unit scale. This is what
   makes a phone trace and a clinical tablet trace comparable.
5. **`lowPass`** — order-4 Butterworth at **15 Hz**, applied
   zero-phase with `filtfilt`.

Feature extraction runs on the output of step 5 at the same 100 Hz.

## featureOrder

`SPIRAL_FEATURE_ORDER` in [app/nt-features.js](../app/nt-features.js) is the
single source of this order, and `model.json`'s `featureOrder` is checked against
it at load — a mismatch stops the results screen with a visible error rather than
scoring through it.

**Frozen and append-only.** Never reorder and never rename: `model.json` stores
`mean`, `scale` and `weights` positionally, so moving one key silently re-points
eleven others.

| Index | Key |
|---|---|
| 0 | `spiral_duration` |
| 1 | `spiral_max_deviation` |
| 2 | `spiral_mean_deviation` |
| 3 | `spiral_std_deviation` |
| 4 | `spiral_major_reversals` |
| 5 | `spiral_mean_speed` |
| 6 | `spiral_std_speed` |
| 7 | `spiral_ldlj` |
| 8 | `spiral_sparc` |
| 9 | `spiral_tremor_4_6` |
| 10 | `spiral_tremor_6_12` |
| 11 | `spiral_tremor_dominant_hz` |

`spiral_sparc` returns `NaN` when the trace is too short to give the spectral arc
length a usable band. That is a valid result, not a failure — the results screen
drops that row and the scorer substitutes the training mean so the feature
contributes nothing.
