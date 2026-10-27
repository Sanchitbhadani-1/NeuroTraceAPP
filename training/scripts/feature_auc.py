# FEATURE_AUC.PY PRINTS THE AUC OF EACH FEATURE ON ITS OWN, FOR EACH DATASET SIDE BY SIDE
# RUN IT WITH python scripts/feature_auc.py results/features_uci395.csv results/features_pahaw.csv

import sys

import pandas as pd
from sklearn.metrics import roc_auc_score


# The columns that are not features
META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

# Read each feature table given on the command line
dfs = []
for p in sys.argv[1:]:
    d = pd.read_csv(p)

    # If the table has hw_dataset rows, keep only those rows
    if "release" in d.columns and (d["release"] == "hw_dataset").any():
        d = d[d["release"] == "hw_dataset"]

    dfs.append(d)

# List every feature column found in any of the tables
feats = []
for d in dfs:
    for c in d.columns:
        if c not in META and c not in feats:
            feats.append(c)

# Print the header row with the name of each file
print(f"{'feature':28s}" + "".join(f"{p.split('/')[-1][:18]:>20s}" for p in sys.argv[1:]))

# Print one row for each feature with its AUC in each table
for f in feats:
    row = f"{f:28s}"
    for d in dfs:

        # Print a dash if the table does not have the feature or has fewer than 5 values for it
        if f not in d.columns or d[f].notna().sum() < 5:
            row += f"{'-':>20s}"
            continue

        # Fill missing values with the median and work out the AUC
        v = d[f].fillna(d[f].median())
        row += f"{roc_auc_score(d['label'], v):20.3f}"
    print(row)
