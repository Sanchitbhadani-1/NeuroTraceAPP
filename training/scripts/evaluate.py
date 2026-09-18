"""Honest cross-validated estimate of how well the features separate PD from HC.

Usage:
    python scripts/evaluate.py features.csv [--release hw_dataset] [--repeats 30]

Patient-level splits (StratifiedGroupKFold on subject_id), repeated over seeds so
the answer is a RANGE, not a point. Reports AUC and balanced accuracy.
"""

import argparse
import warnings

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

META = {"subject_id", "label", "source", "release", "task", "fs_raw", "n_raw"}

# Features known to be broken on real data (see docs/DATASETS.md)
# Nothing is excluded any more: the four that were broken on real data were
# replaced in features.py on Sep 13. Kept as a hook in case a new one goes bad.
BROKEN = set()


def feature_sets(df):
    all_f = [c for c in df.columns if c not in META]
    trusted = [c for c in all_f if c not in BROKEN]
    tremor = [c for c in all_f if "tremor" in c]
    geom = [c for c in all_f if "deviation" in c or "reversals" in c]
    return {"all": all_f, "trusted": trusted, "geometry_only": geom,
            "tremor_only": tremor, "tremor_4_6_alone": ["spiral_tremor_4_6"]}


def models():
    return {
        "logreg": lambda: make_pipeline(
            StandardScaler(),
            LogisticRegression(C=0.5, class_weight="balanced", max_iter=2000)),
        "gboost": lambda: HistGradientBoostingClassifier(
            max_depth=2, max_iter=60, learning_rate=0.1,
            min_samples_leaf=4, class_weight="balanced"),
    }


def cv_scores(X, y, groups, make_model, n_splits, repeats):
    aucs, baccs = [], []
    for seed in range(repeats):
        cv = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)
        prob = np.full(len(y), np.nan)
        for tr, te in cv.split(X, y, groups):
            m = make_model()
            m.fit(X[tr], y[tr])
            prob[te] = m.predict_proba(X[te])[:, 1]
        aucs.append(roc_auc_score(y, prob))
        baccs.append(balanced_accuracy_score(y, prob >= 0.5))
    return np.array(aucs), np.array(baccs)


def fmt(a):
    return f"{np.median(a):.3f}  [{np.percentile(a, 5):.3f}–{np.percentile(a, 95):.3f}]"


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
    print(f"{args.splits}-fold, {args.repeats} repeats, patient-level splits. median [5th–95th pct]\n")

    # --- how bad the sample-rate confound is, as context
    if df["fs_raw"].nunique() > 1:
        a, _ = cv_scores(df[["fs_raw"]].values, y, groups, models()["logreg"], args.splits, args.repeats)
        print(f"CONFOUND  fs_raw alone predicts the label at AUC {fmt(a)}")
        print("          Do NOT read a feature's correlation with fs_raw as leakage here.")
        print("          fs_raw almost IS the label in this dataset, so any feature that")
        print("          works must correlate with it. The real test holds the person")
        print("          fixed and changes only the rate - see docs/DATASETS.md.\n")

    warnings.filterwarnings("ignore")
    for fname, cols in feature_sets(df).items():
        if fname == "trusted" and len(cols) == len([c for c in df.columns if c not in META]):
            continue
        X = df[cols].values.astype(float)
        print(f"[{fname}]  {len(cols)} features")
        for mname, make in models().items():
            if fname in ("tremor_4_6_alone",) and mname == "gboost":
                continue
            a, b = cv_scores(X, y, groups, make, args.splits, args.repeats)
            print(f"   {mname:7s}  AUC {fmt(a)}   bal.acc {fmt(b)}")
        print()


if __name__ == "__main__":
    main()
