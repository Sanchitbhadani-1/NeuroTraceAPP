"""Single-feature AUC on each dataset, side by side.

    python scripts/feature_auc.py results/features_uci395.csv results/features_pahaw.csv

>0.5 means patients score HIGHER. A feature that FLIPS sides between datasets
is measuring the dataset, not the disease. Near 0.5 everywhere is noise.
Descriptive only - no held-out data here, so never quote these as accuracy.
"""

import sys

import pandas as pd
from sklearn.metrics import roc_auc_score

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

dfs = []
for p in sys.argv[1:]:
    d = pd.read_csv(p)

    if "release" in d.columns and (d["release"] == "hw_dataset").any():
        d = d[d["release"] == "hw_dataset"]
    # UCI's new_dataset has no controls, so it cannot be compared against

    dfs.append(d)

feats = []
for d in dfs:
    for c in d.columns:
        if c not in META and c not in feats:
            feats.append(c)
# Union, not intersection - UCI has no in-air columns and we still want the row

print(f"{'feature':28s}" + "".join(f"{p.split('/')[-1][:18]:>20s}" for p in sys.argv[1:]))

for f in feats:
    row = f"{f:28s}"
    for d in dfs:

        if f not in d.columns or d[f].notna().sum() < 5:
            row += f"{'-':>20s}"
            continue
        # A dash, not a crash, when this table does not have that feature

        v = d[f].fillna(d[f].median())
        row += f"{roc_auc_score(d['label'], v):20.3f}"
    print(row)
