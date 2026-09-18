"""Runs every recording through preprocess + extract and writes one feature table.

Usage:
    python scripts/build_features.py <uci395_root> [out.csv]

Only aggregate numbers go in the table - never coordinate rows. Safe to share.
"""

import sys
import warnings

import numpy as np
import pandas as pd

from neurotrace.datasets import iter_uci
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features

FS = 100.0


def build(root):
    rows, skipped = [], []
    for rec in iter_uci(root):
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                t, x, y = preprocess_trace(rec["t"], rec["x"], rec["y"], fs=FS)
                f = extract_spiral_features(t, x, y, fs=FS)
        except ValueError as e:
            skipped.append((rec["subject_id"], str(e)))
            continue
        # The library is strict on purpose; the batch job says what it skipped

        rows.append({
            "subject_id": rec["subject_id"],
            "label": rec["label"],
            "source": rec["source"],
            "release": rec["subject_id"].split(":")[1],
            "task": rec["task"],
            "fs_raw": rec["fs"],
            # fs_raw is here so the leakage check can see it. It is NOT a feature
            "n_raw": len(rec["t"]),
            **f,
        })
    for sid, why in skipped:
        print(f"  SKIPPED {sid}: {why}")
    return pd.DataFrame(rows)


if __name__ == "__main__":
    root = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "features_uci395.csv"
    df = build(root)
    df.to_csv(out, index=False)
    print(f"{len(df)} rows -> {out}")
    print(df.groupby(["release", "label"]).size())
