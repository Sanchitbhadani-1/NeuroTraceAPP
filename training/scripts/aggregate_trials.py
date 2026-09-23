"""Collapse per-trial rows to one row per person per session, by averaging.

    python scripts/aggregate_trials.py results/features_collected.csv results/features_collected_agg.csv

Three drawings averaged is a steadier measurement than one. The reference and
the model both use the averaged table; the per-trial one is kept so noise.py
can say how much the averaging actually bought.
"""

import sys

import pandas as pd

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

df = pd.read_csv(sys.argv[1])
feats = [c for c in df.columns if c not in META]

agg = (df.groupby(["subject_id", "session"], as_index=False)
         .agg({**{c: "mean" for c in feats},
               **{c: "first" for c in META - {"subject_id", "session", "trial"}},
               "trial": "count"})
         .rename(columns={"trial": "n_trials"}))
# Features get averaged, the labels just come along, and counting the trials
# turns that column into how many there were

agg.to_csv(sys.argv[2], index=False)
print(f"{len(df)} trials -> {len(agg)} person-sessions -> {sys.argv[2]}")
print(agg["n_trials"].value_counts().sort_index().rename("sessions with N trials"))
