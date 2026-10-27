# AGGREGATE_TRIALS.PY AVERAGES THE TRIAL ROWS INTO ONE ROW PER PERSON PER SESSION
# RUN IT WITH python scripts/aggregate_trials.py results/features_collected.csv results/features_collected_agg.csv

import sys

import pandas as pd


# The columns that are not features
META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

# Read the trial table and list its feature columns
df = pd.read_csv(sys.argv[1])
feats = [c for c in df.columns if c not in META]

# Group the rows by person and session, average the features, and keep the first value of the other columns
# Count the trials into a new n_trials column
agg = (df.groupby(["subject_id", "session"], as_index=False)
         .agg({**{c: "mean" for c in feats},
               **{c: "first" for c in META - {"subject_id", "session", "trial"}},
               "trial": "count"})
         .rename(columns={"trial": "n_trials"}))

# Save the averaged table and print how many sessions have each number of trials
agg.to_csv(sys.argv[2], index=False)
print(f"{len(df)} trials -> {len(agg)} person-sessions -> {sys.argv[2]}")
print(agg["n_trials"].value_counts().sort_index().rename("sessions with N trials"))
