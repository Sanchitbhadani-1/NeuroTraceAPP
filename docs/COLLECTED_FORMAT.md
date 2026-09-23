# Collected-trace format

What the app's collection screen exports, and what `neurotrace/collected.py`
reads. One export = one person, one sitting, N trials. Several sessions may be
packed into one file as a JSON array.

```json
{
  "formatVersion": 1,
  "subjectId": "a7f3c2",
  "session": 1,
  "collectedAt": "2026-09-27T14:12:00Z",
  "deviceLabel": "iPad Pro 11 (M4)",
  "inputType": "pencil",
  "hand": "right",
  "age": 74,
  "diagnosis": "none",
  "medicationHoursAgo": null,
  "consent": true,
  "trials": [
    {
      "trial": 1,
      "task": "spiral",
      "samples": [
        { "t": 0.000, "x": 412.5, "y": 388.0, "pressure": 0.41 },
        { "t": 0.004, "x": 413.1, "y": 387.2, "pressure": 0.43 }
      ]
    },
    { "trial": 2, "task": "spiral", "samples": [] },
    { "trial": 3, "task": "spiral", "samples": [] }
  ]
}
```

| field | rules |
|---|---|
| `subjectId` | random, assigned on first visit, **stored on the device** so a return visit reuses it. Never a name, never derived from one. |
| `session` | 1 on the first visit, 2 on the next. Same `subjectId`. |
| `age` | integer. `collected.py` turns it into a bracket (`50s` / `60s` / `70s` / `80+`). Optionally send `ageBracket` instead. |
| `diagnosis` | `none` \| `parkinsons` \| `essential_tremor` \| `other`. Only `none` enters the healthy reference. `parkinsons` is label 1. Everything else is kept but excluded from both. |
| `medicationHoursAgo` | patients only; null otherwise. Rough is fine. |
| `hand` | `left` \| `right`. The hand that drew. |
| `inputType` | `pencil` \| `touch` \| `mouse`. From `PointerEvent.pointerType`. |
| `samples` | every `pointermove` while down. `t` seconds since the trial's first sample; `x`, `y` canvas pixels; `pressure` 0–1, 0 when unsupported. |

## Pen lifts

**Keep every stroke.** If the pen lifts and comes back, the samples continue
in the same `samples` array with a gap in `t`. Do not reset on `pointerdown`.
The gap *is* data — pen lifts track disease severity (`docs/DATASETS.md`).

## Three trials

The collection screen asks for three spirals. `build_features.py` makes one
row per trial; `aggregate_trials.py` averages them. The reference and the
scoring both use the average, so users and reference are measured the same way.

## What the pipeline does with it

```
exports/*.json
   → build_features.py --source collected   → features_collected.csv        (one row per trial)
   → aggregate_trials.py                    → features_collected_agg.csv    (one row per person-session)
   → noise.py                               ← per-trial table: within-person noise, what averaging buys
   → export_model.py --reference features_collected_agg.csv → app/reference.json
```
