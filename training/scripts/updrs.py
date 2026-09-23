"""Within PaHaW PATIENTS only: does any feature track clinical severity?

    python scripts/updrs.py results/features_pahaw.csv <corpus_PaHaW.xlsx>

Separating patients from controls is one question. Tracking how BAD it is
within patients is a different one, and it survives even when the first fails.
Spearman because UPDRS is an ordinal scale. Aggregate output only.
"""

import sys

import pandas as pd
from scipy.stats import spearmanr

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

df = pd.read_csv(sys.argv[1])
meta = pd.read_excel(sys.argv[2])

meta["subject_id"] = meta["ID"].map(lambda i: f"pahaw:{int(i):05d}")
# Rebuild the same id extract_pahaw wrote, so the merge lines up

pts = df[df["label"] == 1].merge(meta[["subject_id", "UPDRS V", "Length of PD", "LED", "Age"]], on="subject_id")
pts = pts.dropna(subset=["UPDRS V"])
print(f"{len(pts)} patients with a UPDRS V score\n")

for target in ("UPDRS V", "Length of PD", "LED", "Age"):

    if target not in pts.columns or pts[target].notna().sum() < 10:
        continue
    # Age is here to check the finding is not just older people lifting more

    print(f"--- {target} ---")
    print(f"{'feature':28s} {'rho':>7s} {'p':>8s}")

    rows = []
    for c in df.columns:
        if c in META or pts[c].notna().sum() < 10:
            continue
        rho, p = spearmanr(pts[c], pts[target], nan_policy="omit")
        rows.append((abs(rho), c, rho, p))

    for _, c, rho, p in sorted(rows, reverse=True):
        flag = "  <--" if p < 0.05 else ""
        print(f"{c:28s} {rho:+7.3f} {p:8.4f}{flag}")
    print()
