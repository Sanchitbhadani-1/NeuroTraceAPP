"""Train the shipping model and write what the app loads.

    PYTHONPATH=. python scripts/export_model.py results/features_uci395.csv results/features_pahaw.csv \
        [--reference results/features_collected_agg.csv] [--C 0.05]

Two files, two different questions:
  app/model.json      DIRECTION - what "worse" looks like
  app/reference.json  THE RULER - what normal looks like on OUR device

The app never sees a training mean. It standardizes against reference.json,
applies model.json, and reads the percentile off reference.json.
"""

import argparse
import datetime
import json
import sys

sys.path.insert(0, "scripts")

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score
from sklearn.model_selection import StratifiedGroupKFold

from neurotrace.synth import create_spiral_synth
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features
from neurotrace.collected import BRACKETS

MIN_BRACKET_N = 12
# Fewer than this in an age bracket and the app falls back to "all"


# --- 1. load ---------------------------------------------------------

def load_training(path):

    df = pd.read_csv(path)

    if "release" in df.columns and (df["release"] == "hw_dataset").any():
        df = df[df["release"] == "hw_dataset"]
    # UCI's new_dataset has no controls, so it cannot be compared against

    if "diagnosis" in df.columns:
        df = df[df["diagnosis"].isin(["none", "parkinsons"])]
    # Essential tremor is neither, so it is not in the PD-vs-healthy model

    return df.reset_index(drop=True)


# THE FIX. Each dataset's OWN healthy people are its ruler
def healthy_standardize(df, cols):

    hc = df[df["label"] == 0][cols]
    mu, sd = hc.mean(), hc.std(ddof=0).replace(0, 1.0)

    return ((df[cols] - mu) / sd).values
    # "+2" now means "two healthy-SDs above normal" on ANY tablet. A pooled
    # scaler put 83% of healthy Czechs in the top 5% of the UCI reference


# --- 2. train --------------------------------------------------------

def fit(X, y, C):
    return LogisticRegression(C=C, class_weight="balanced", max_iter=2000).fit(X, y)


def cross_validate(X, y, groups, src, C, repeats=30):

    aucs, baccs, within = [], [], {s: [] for s in np.unique(src)}
    for seed in range(repeats):

        prob = np.full(len(y), np.nan)
        for tr, te in StratifiedGroupKFold(5, shuffle=True, random_state=seed).split(X, y, groups):
            prob[te] = fit(X[tr], y[tr], C).predict_proba(X[te])[:, 1]

        aucs.append(roc_auc_score(y, prob))
        baccs.append(balanced_accuracy_score(y, prob >= 0.5))

        for s in within:
            m = src == s
            within[s].append(roc_auc_score(y[m], prob[m]))
        # Per dataset too - that is where the medication story shows up

    p = lambda a: np.percentile(a, [5, 50, 95]).tolist()
    return p(aucs), p(baccs), {s: p(v) for s, v in within.items()}


# --- 3. reference ----------------------------------------------------

def bracket_block(hc, cols, weights, bias):

    mu, sd = hc[cols].mean(), hc[cols].std(ddof=0).replace(0, 1.0)

    z = ((hc[cols] - mu) / sd).values
    score = 1 / (1 + np.exp(-(bias + z @ weights)))
    # Every reference person scored against their OWN bracket, so a user's
    # percentile means "among people like you"

    return {
        "n": int(len(hc)),
        "mean": mu.tolist(),
        "sd": sd.tolist(),
        "features": {c: sorted(hc[c].tolist()) for c in cols},
        "score": sorted(score.tolist()),
    }


def build_reference(df, cols, weights, bias, device_matched, source):

    hc = df[df["diagnosis"] == "none"] if "diagnosis" in df.columns else df[df["label"] == 0]
    # diagnosis, NOT label - essential tremor is label 0 and is not healthy

    out = {
        "version": 2,
        "task": "spiral",
        "featureOrder": cols,
        "source": source,
        "deviceMatched": device_matched,
        "trialsPerSession": int(df["n_trials"].median()) if "n_trials" in df.columns else 1,
        "minBracketN": MIN_BRACKET_N,
        "brackets": {"all": bracket_block(hc, cols, weights, bias)},
    }

    if "age_bracket" in hc.columns:
        for b in BRACKETS:
            sub = hc[hc["age_bracket"] == b]
            if len(sub) >= MIN_BRACKET_N:
                out["brackets"][b] = bracket_block(sub, cols, weights, bias)
    # A thin bracket is worse than none - the app falls back to "all"

    return out


# --- main ------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("training", nargs="+", help="feature CSVs with patients AND controls")
    ap.add_argument("--reference", help="aggregated collected CSV; healthy rows become the ruler")
    ap.add_argument("--C", type=float, default=0.05)
    ap.add_argument("--out-dir", default="../app")
    args = ap.parse_args()

    sets = {p.split("/")[-1].replace("features_", "").replace(".csv", ""): load_training(p)
            for p in args.training}

    cols = [c for c in next(iter(sets.values())).columns if c.startswith("spiral_")]

    expected = list(extract_spiral_features(*preprocess_trace(*create_spiral_synth()), fs=100.0).keys())
    assert cols == expected, f"CSV columns {cols} != featureOrder {expected}"
    # Refuse to write weights that would land on the wrong features

    X = np.vstack([healthy_standardize(d, cols) for d in sets.values()])
    y = np.concatenate([d["label"].values for d in sets.values()])
    groups = np.concatenate([d["subject_id"].values for d in sets.values()])
    src = np.concatenate([[name] * len(d) for name, d in sets.items()])

    cv_auc, cv_bacc, within = cross_validate(X, y, groups, src, args.C)
    print(f"combined  AUC {cv_auc[1]:.3f} [{cv_auc[0]:.3f}-{cv_auc[2]:.3f}]   bal.acc {cv_bacc[1]:.3f}")
    for s, v in within.items():
        print(f"  within {s:10s} AUC {v[1]:.3f} [{v[0]:.3f}-{v[2]:.3f}]")

    model = fit(X, y, args.C)
    weights = model.coef_[0]
    bias = float(model.intercept_[0])

    model_out = {
        "version": 2,
        "task": "spiral",
        "featureOrder": cols,

        "units": "healthy_sd",
        # The app MUST standardize against reference.json before applying these

        "weights": weights.tolist(),
        "bias": bias,
        "trainedOn": {
            "date": datetime.date.today().isoformat(),
            "sources": list(sets),
            "nHealthy": int((y == 0).sum()),
            "nPatients": int((y == 1).sum()),
            "C": args.C,
            "cvAuc": cv_auc,
            "cvBalancedAccuracy": cv_bacc,
            "withinDataset": within,
        },
        # So the app can say where the comparison came from instead of
        # hardcoding a sentence someone forgets to update
    }
    with open(f"{args.out_dir}/model.json", "w") as f:
        json.dump(model_out, f, indent=2)

    if args.reference:
        ref_df = pd.read_csv(args.reference)
        ref = build_reference(ref_df, cols, weights, bias, True, "neurotrace collected")
    else:
        biggest = max(sets.items(), key=lambda kv: (kv[1]["label"] == 0).sum())
        ref = build_reference(biggest[1], cols, weights, bias, False, f"{biggest[0]} controls (stand-in)")
        print(f"\nNO COLLECTED DATA - reference is {biggest[0]}'s controls, deviceMatched: false")
    # Until we have our own testers, the biggest set of controls stands in

    with open(f"{args.out_dir}/reference.json", "w") as f:
        json.dump(ref, f, indent=2)

    print(f"\nreference: {ref['source']}, brackets " +
          ", ".join(f"{b}={blk['n']}" for b, blk in ref["brackets"].items()))
    print(f"wrote {args.out_dir}/model.json and {args.out_dir}/reference.json")


if __name__ == "__main__":
    main()
