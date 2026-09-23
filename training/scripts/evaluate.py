"""Cross-validated AUC by feature group.

    python scripts/evaluate.py features.csv [--release hw_dataset] [--repeats 30]

Patient-level splits, repeated over seeds, so the answer is a RANGE not a point.
Groups are built from column PREFIXES, so the same script runs on a spiral
table, a writing table, or one with the experimental columns.
"""

import argparse
import warnings

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}

BROKEN = {"spiral_tremor_6_12"}
# Flips sign between UCI and PaHaW - it measures the tablet. Braces not set(),
# set("abc") explodes a string into single letters and excludes nothing


def feature_sets(df):

    usable = [c for c in df.columns if c not in META and df[c].notna().mean() > 0.5]
    # Drop a column that is mostly empty - inair_* on UCI, which has no lifts

    base = [c for c in usable if c.startswith(("spiral_", "writing_"))]
    pressure = [c for c in usable if c.startswith("pressure_")]
    inair = [c for c in usable if c.startswith("inair_")]

    sets = {"base": base}
    if BROKEN & set(base):
        sets["base_trusted"] = [c for c in base if c not in BROKEN]
    if pressure:
        sets["pressure_only"] = pressure
        sets["base+pressure"] = base + pressure
    if inair:
        sets["inair_only"] = inair
        sets["base+inair"] = base + inair
    if pressure and inair:
        sets["base+pressure+inair"] = base + pressure + inair
    # COMBINATIONS matter - pressure alone looked fine and still LOWERED the
    # combined score

    geom = [c for c in base if "deviation" in c or "reversals" in c]
    motion = [c for c in base if any(k in c for k in ("speed", "ldlj", "sparc", "duration"))]
    tremor = [c for c in base if "tremor" in c]
    if geom: sets["geometry_only"] = geom
    if motion: sets["motion_only"] = motion
    if tremor: sets["tremor_only"] = tremor
    return sets


def models():
    return {
        "logreg": lambda: make_pipeline(
            SimpleImputer(strategy="median"),
            StandardScaler(),
            LogisticRegression(C=0.5, class_weight="balanced", max_iter=2000)),
        "gboost": lambda: HistGradientBoostingClassifier(
            max_depth=2, max_iter=60, learning_rate=0.1,
            min_samples_leaf=4, class_weight="balanced"),
    }
    # Imputer is INSIDE the pipeline so the median is computed per fold and
    # never sees the test rows


def cv_scores(X, y, groups, make_model, n_splits, repeats):

    aucs, baccs = [], []
    for seed in range(repeats):
        cv = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)

        prob = np.full(len(y), np.nan)
        for tr, te in cv.split(X, y, groups):
            m = make_model()
            m.fit(X[tr], y[tr])
            prob[te] = m.predict_proba(X[te])[:, 1]
        # Every person scored by a model that never trained on them

        aucs.append(roc_auc_score(y, prob))
        baccs.append(balanced_accuracy_score(y, prob >= 0.5))

    return np.array(aucs), np.array(baccs)


def fmt(a):
    return f"{np.median(a):.3f}  [{np.percentile(a, 5):.3f}-{np.percentile(a, 95):.3f}]"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--release", default=None)
    ap.add_argument("--repeats", type=int, default=30)
    ap.add_argument("--splits", type=int, default=5)
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    if args.release:
        df = df[df["release"] == args.release].reset_index(drop=True)

    y = df["label"].values
    groups = df["subject_id"].values

    n0, n1 = (y == 0).sum(), (y == 1).sum()
    print(f"n = {len(df)}  ({n0} HC, {n1} PD)   majority-class accuracy = {max(n0, n1) / len(df):.3f}")
    print(f"{args.splits}-fold, {args.repeats} repeats, patient-level splits. median [5th-95th pct]\n")

    if df["fs_raw"].nunique() > 1:
        a, _ = cv_scores(df[["fs_raw"]].values, y, groups, models()["logreg"], args.splits, args.repeats)
        print(f"CONFOUND  fs_raw alone predicts the label at AUC {fmt(a)}")
        print("          NOT a leakage test - fs_raw tracks the dataset and so does the")
        print("          label, so any feature that works must correlate with it. The real")
        print("          test holds the person fixed and changes only the rate.\n")

    warnings.filterwarnings("ignore")
    for fname, cols in feature_sets(df).items():
        X = df[cols].values.astype(float)
        print(f"[{fname}]  {len(cols)} features")
        for mname, make in models().items():
            a, b = cv_scores(X, y, groups, make, args.splits, args.repeats)
            print(f"   {mname:7s}  AUC {fmt(a)}   bal.acc {fmt(b)}")
        print()


if __name__ == "__main__":
    main()
