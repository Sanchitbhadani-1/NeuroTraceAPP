# BUILD_FEATURES.PY CLEANS EVERY RECORDING, MEASURES ITS FEATURES, AND SAVES THEM ALL IN ONE TABLE
# COLLECTED RECORDINGS GIVE ONE ROW FOR EACH TRIAL
# RUN IT WITH PYTHONPATH=. python scripts/build_features.py <root> <out.csv> [--source uci|collected]

import argparse
import warnings

import pandas as pd

from neurotrace.datasets import iter_uci
from neurotrace.collected import iter_collected
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features
from neurotrace.extra import pressure_features


# The number of points per second the drawings are resampled to
FS = 100.0


# Clean one recording and measure its features
def extract(rec):

    # Clean the drawing and measure the spiral features, hiding any warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        t, x, y = preprocess_trace(rec["t"], rec["x"], rec["y"], fs=FS)
        f = extract_spiral_features(t, x, y, fs=FS)

    # Add the pressure features, measured from the raw times and pressures
    f.update(pressure_features(rec["t"], rec["pressure"]))

    return f


# Measure every recording and put the results in one table
def build(records):

    rows, skipped = [], []
    for rec in records:

        # Measure the recording, or note it and move on if it fails
        try:
            f = extract(rec)
        except ValueError as e:
            skipped.append((rec["subject_id"], rec.get("trial", 1), str(e)))
            continue

        # Add a row with the recording's details and its features
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

            # The raw number of points per second, kept as a detail and not a feature
            "fs_raw": rec["fs"],

            "n_raw": len(rec["t"]),
            **f,
        })

    # Print each recording that was skipped and why
    for sid, trial, why in skipped:
        print(f"  SKIPPED {sid} trial {trial}: {why}")
    return pd.DataFrame(rows)


if __name__ == "__main__":

    # Read the data folder, the output file, and the data source
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--source", choices=("uci", "collected"), default="uci")
    args = ap.parse_args()

    # Load the recordings, build the table, save it, and print the row counts
    records = iter_uci(args.root) if args.source == "uci" else iter_collected(args.root)
    df = build(records)
    df.to_csv(args.out, index=False)
    print(f"{len(df)} rows -> {args.out}")
    print(df.groupby(["release", "label"]).size())
