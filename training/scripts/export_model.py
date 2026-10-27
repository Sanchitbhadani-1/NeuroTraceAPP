# EXPORT_MODEL.PY TRAINS THE FINAL MODEL AND WRITES MODEL.JSON AND REFERENCE.JSON FOR THE APP
# RUN IT WITH PYTHONPATH=. python scripts/export_model.py results/features_uci395.csv results/features_pahaw.csv [--reference results/features_collected_agg.csv] [--C 0.05]

import argparse
import datetime
import json
import sys

# Let Python find the other files in scripts/
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


# The fewest healthy people an age bracket needs to get its own block in reference.json
MIN_BRACKET_N = 12


# LOAD

# Read a feature table and keep only the rows used for training
def load_training(path):

    df = pd.read_csv(path)

    # If the table has hw_dataset rows, keep only those rows
    if "release" in df.columns and (df["release"] == "hw_dataset").any():
        df = df[df["release"] == "hw_dataset"]

    # Keep only the people with no diagnosis or with Parkinson's
    if "diagnosis" in df.columns:
        df = df[df["diagnosis"].isin(["none", "parkinsons"])]

    return df.reset_index(drop=True)


# Scale each feature by the mean and spread of the dataset's own healthy people
def healthy_standardize(df, cols):

    hc = df[df["label"] == 0][cols]
    mu, sd = hc.mean(), hc.std(ddof=0).replace(0, 1.0)

    return ((df[cols] - mu) / sd).values


# TRAIN

# Train a logistic regression model
def fit(X, y, C):
    return LogisticRegression(C=C, class_weight="balanced", max_iter=2000).fit(X, y)


# Run 5 fold cross validation many times and give back the AUC and balanced accuracy percentiles
def cross_validate(X, y, groups, src, C, repeats=30):

    aucs, baccs, within = [], [], {s: [] for s in np.unique(src)}
    for seed in range(repeats):

        # Score each person with a model that was trained without them
        prob = np.full(len(y), np.nan)
        for tr, te in StratifiedGroupKFold(5, shuffle=True, random_state=seed).split(X, y, groups):
            prob[te] = fit(X[tr], y[tr], C).predict_proba(X[te])[:, 1]

        aucs.append(roc_auc_score(y, prob))
        baccs.append(balanced_accuracy_score(y, prob >= 0.5))

        # Work out the AUC inside each dataset too
        for s in within:
            m = src == s
            within[s].append(roc_auc_score(y[m], prob[m]))

    # Give back the 5th, 50th and 95th percentiles of each
    p = lambda a: np.percentile(a, [5, 50, 95]).tolist()
    return p(aucs), p(baccs), {s: p(v) for s, v in within.items()}


# REFERENCE

# Build the reference block for one group of healthy people
def bracket_block(hc, cols, weights, bias):

    mu, sd = hc[cols].mean(), hc[cols].std(ddof=0).replace(0, 1.0)

    # Score every person in the group against the group's own mean and spread
    z = ((hc[cols] - mu) / sd).values
    score = 1 / (1 + np.exp(-(bias + z @ weights)))

    # Give back the count, means, spreads, sorted feature values and sorted scores
    return {
        "n": int(len(hc)),
        "mean": mu.tolist(),
        "sd": sd.tolist(),
        "features": {c: sorted(hc[c].tolist()) for c in cols},
        "score": sorted(score.tolist()),
    }


# Build reference.json from the healthy people in a table
def build_reference(df, cols, weights, bias, device_matched, source):

    # Take the people with no diagnosis, or with label 0 if there is no diagnosis column
    hc = df[df["diagnosis"] == "none"] if "diagnosis" in df.columns else df[df["label"] == 0]

    # Start with a block for everyone
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

    # Add a block for each age bracket that has at least MIN_BRACKET_N people
    if "age_bracket" in hc.columns:
        for b in BRACKETS:
            sub = hc[hc["age_bracket"] == b]
            if len(sub) >= MIN_BRACKET_N:
                out["brackets"][b] = bracket_block(sub, cols, weights, bias)

    return out


# MAIN

# Train the model, print its scores, and write model.json and reference.json
def main():

    # Read the command line settings
    ap = argparse.ArgumentParser()
    ap.add_argument("training", nargs="+", help="feature CSVs with patients AND controls")
    ap.add_argument("--reference", help="aggregated collected CSV; healthy rows become the ruler")
    ap.add_argument("--C", type=float, default=0.05)
    ap.add_argument("--out-dir", default="../app/old-website")
    args = ap.parse_args()

    # Load each training table, named after its file
    sets = {p.split("/")[-1].replace("features_", "").replace(".csv", ""): load_training(p)
            for p in args.training}

    # List the spiral feature columns
    cols = [c for c in next(iter(sets.values())).columns if c.startswith("spiral_")]

    # Stop if the columns are not in the same order as the features the code makes
    expected = list(extract_spiral_features(*preprocess_trace(*create_spiral_synth()), fs=100.0).keys())
    assert cols == expected, f"CSV columns {cols} != featureOrder {expected}"

    # Scale each dataset by its own healthy people and stack them together
    X = np.vstack([healthy_standardize(d, cols) for d in sets.values()])
    y = np.concatenate([d["label"].values for d in sets.values()])
    groups = np.concatenate([d["subject_id"].values for d in sets.values()])
    src = np.concatenate([[name] * len(d) for name, d in sets.items()])

    # Run cross validation and print the results
    cv_auc, cv_bacc, within = cross_validate(X, y, groups, src, args.C)
    print(f"combined  AUC {cv_auc[1]:.3f} [{cv_auc[0]:.3f}-{cv_auc[2]:.3f}]   bal.acc {cv_bacc[1]:.3f}")
    for s, v in within.items():
        print(f"  within {s:10s} AUC {v[1]:.3f} [{v[0]:.3f}-{v[2]:.3f}]")

    # Train the final model on everyone
    model = fit(X, y, args.C)
    weights = model.coef_[0]
    bias = float(model.intercept_[0])

    # Build model.json
    model_out = {
        "version": 2,
        "task": "spiral",
        "featureOrder": cols,

        # The weights work on features scaled by healthy standard deviations
        "units": "healthy_sd",

        "weights": weights.tolist(),
        "bias": bias,

        # The date, data sources, counts, settings and cross validation scores
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
    }

    # Save model.json
    with open(f"{args.out_dir}/model.json", "w") as f:
        json.dump(model_out, f, indent=2)

    # Build the reference from the collected table if one is given, or else from the training set with the most healthy people
    if args.reference:
        ref_df = pd.read_csv(args.reference)
        ref = build_reference(ref_df, cols, weights, bias, True, "neurotrace collected")
    else:
        biggest = max(sets.items(), key=lambda kv: (kv[1]["label"] == 0).sum())
        ref = build_reference(biggest[1], cols, weights, bias, False, f"{biggest[0]} controls (stand-in)")
        print(f"\nNO COLLECTED DATA - reference is {biggest[0]}'s controls, deviceMatched: false")

    # Save reference.json
    with open(f"{args.out_dir}/reference.json", "w") as f:
        json.dump(ref, f, indent=2)

    # Print the reference source, the size of each bracket, and the files written
    print(f"\nreference: {ref['source']}, brackets " +
          ", ".join(f"{b}={blk['n']}" for b, blk in ref["brackets"].items()))
    print(f"wrote {args.out_dir}/model.json and {args.out_dir}/reference.json")


if __name__ == "__main__":
    main()
