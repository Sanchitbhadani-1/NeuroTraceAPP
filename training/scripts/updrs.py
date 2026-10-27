# UPDRS.PY CHECKS HOW EACH FEATURE MATCHES UP WITH UPDRS V, YEARS WITH PD, LED AND AGE IN PAHAW PATIENTS
# RUN IT WITH python scripts/updrs.py results/features_pahaw.csv <corpus_PaHaW.xlsx>

import sys

import pandas as pd
from scipy.stats import spearmanr


# The columns that are not features
META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

# Read the feature table and the PaHaW patient sheet
df = pd.read_csv(sys.argv[1])
meta = pd.read_excel(sys.argv[2])

# Turn each sheet ID into the same subject id used in the feature table
meta["subject_id"] = meta["ID"].map(lambda i: f"pahaw:{int(i):05d}")

# Join the patient rows to their scores and keep only the ones with a UPDRS V score
pts = df[df["label"] == 1].merge(meta[["subject_id", "UPDRS V", "Length of PD", "LED", "Age"]], on="subject_id")
pts = pts.dropna(subset=["UPDRS V"])
print(f"{len(pts)} patients with a UPDRS V score\n")

# Check each score in turn
for target in ("UPDRS V", "Length of PD", "LED", "Age"):

    # Skip the score if it is missing or has fewer than 10 values
    if target not in pts.columns or pts[target].notna().sum() < 10:
        continue

    print(f"--- {target} ---")
    print(f"{'feature':28s} {'rho':>7s} {'p':>8s}")

    # Work out the Spearman rho and p value for each feature with at least 10 values
    rows = []
    for c in df.columns:
        if c in META or pts[c].notna().sum() < 10:
            continue
        rho, p = spearmanr(pts[c], pts[target], nan_policy="omit")
        rows.append((abs(rho), c, rho, p))

    # Print the features from the largest rho to the smallest, marking p values under 0.05
    for _, c, rho, p in sorted(rows, reverse=True):
        flag = "  <--" if p < 0.05 else ""
        print(f"{c:28s} {rho:+7.3f} {p:8.4f}{flag}")
    print()
