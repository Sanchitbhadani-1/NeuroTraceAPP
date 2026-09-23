"""Every recording through preprocess + extract, into one feature table.

    PYTHONPATH=. python scripts/build_features.py <root> <out.csv> [--source uci|collected]

collected gives one row PER TRIAL, so aggregate_trials.py can average them and
noise.py can measure what the averaging buys.
Aggregate numbers only - never coordinate rows. Safe to share.
"""

import argparse
import warnings

import pandas as pd

from neurotrace.datasets import iter_uci
from neurotrace.collected import iter_collected
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features
from neurotrace.extra import pressure_features

FS = 100.0


def extract(rec):

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        t, x, y = preprocess_trace(rec["t"], rec["x"], rec["y"], fs=FS)
        f = extract_spiral_features(t, x, y, fs=FS)

    f.update(pressure_features(rec["t"], rec["pressure"]))
    # Raw samples, not the resampled trace - pressure is a per-sample reading

    return f


def build(records):

    rows, skipped = [], []
    for rec in records:

        try:
            f = extract(rec)
        except ValueError as e:
            skipped.append((rec["subject_id"], rec.get("trial", 1), str(e)))
            continue
        # Library is strict, batch job is tolerant and says what it skipped

        rows.append({
            "subject_id": rec["subject_id"],
            "label": rec["label"],
            "diagnosis": rec.get("diagnosis", "parkinsons" if rec["label"] else "none"),
            "source": rec["source"],
            "release": rec.get("release", rec["subject_id"].split(":")[1]),
            "task": rec["task"],
            "session": rec.get("session", 1),
            "trial": rec.get("trial", 1),
            "age_bracket": rec.get("age_bracket"),
            "hand": rec.get("hand"),
            "device": rec.get("device"),

            "fs_raw": rec["fs"],
            # Here so the confound check can see it. NOT a feature

            "n_raw": len(rec["t"]),
            **f,
        })

    for sid, trial, why in skipped:
        print(f"  SKIPPED {sid} trial {trial}: {why}")
    return pd.DataFrame(rows)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--source", choices=("uci", "collected"), default="uci")
    args = ap.parse_args()

    records = iter_uci(args.root) if args.source == "uci" else iter_collected(args.root)
    df = build(records)
    df.to_csv(args.out, index=False)
    print(f"{len(df)} rows -> {args.out}")
    print(df.groupby(["release", "label"]).size())
