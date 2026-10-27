# TRANSFER.PY TRAINS A MODEL ON ONE DATASET AND TESTS IT ON THE OTHER, WITH TWO WAYS OF SCALING
# POOLED SCALES BY THE WHOLE TRAINING SET, HEALTHY SCALES EACH DATASET BY ITS OWN HEALTHY PEOPLE
# RUN IT WITH PYTHONPATH=. python scripts/transfer.py results/features_uci395.csv results/features_pahaw.csv

import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score


# The columns that are not features
META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}


# Read a feature table, keeping only the hw_dataset rows if it has any
def load(path):
    d = pd.read_csv(path)
    if "release" in d.columns and (d["release"] == "hw_dataset").any():
        d = d[d["release"] == "hw_dataset"]
    return d.reset_index(drop=True)


# List the spiral feature columns
def feats(d):
    return [c for c in d.columns if c.startswith("spiral_")]


# Scale each feature by the mean and spread of the dataset's own healthy people
def healthy_standardize(d, cols):
    hc = d[d["label"] == 0][cols]
    mu, sd = hc.mean(), hc.std(ddof=0).replace(0, 1.0)
    return ((d[cols] - mu) / sd).values


# Scale the training and test sets by the mean and spread of the whole training set
def pooled_standardize(train, test, cols):
    mu, sd = train[cols].mean(), train[cols].std(ddof=0).replace(0, 1.0)
    return ((train[cols] - mu) / sd).values, ((test[cols] - mu) / sd).values


# Train a logistic regression model
def fit(X, y):
    return LogisticRegression(C=0.5, class_weight="balanced", max_iter=2000).fit(X, y)


# Print the test AUC, balanced accuracy, and where the test people land against the training set's healthy people
def report(name, model, Xtr, ytr, Xte, yte):

    # Score the training and test people
    p_tr = model.predict_proba(Xtr)[:, 1]
    p_te = model.predict_proba(Xte)[:, 1]

    # Find each test person's percentile among the training set's healthy people
    ref = np.sort(p_tr[ytr == 0])
    pct = np.array([100 * (ref < v).mean() for v in p_te])

    # Split the percentiles into healthy and patients and work out the AUC and balanced accuracy
    hc, pd_ = pct[yte == 0], pct[yte == 1]
    auc = roc_auc_score(yte, p_te)
    bacc = balanced_accuracy_score(yte, p_te >= 0.5)

    # Print the results with the median percentile and the share in the top 5% for each group
    print(f"  {name:8s}  AUC {auc:.3f}  bal.acc {bacc:.3f}   "
          f"test HEALTHY land at median {np.median(hc):3.0f}th pct, {100 * (hc >= 95).mean():3.0f}% in top 5%   "
          f"| test PATIENTS median {np.median(pd_):3.0f}th, {100 * (pd_ >= 95).mean():3.0f}% in top 5%")


# Read each feature table, named after its file, and list the features
sets = {p.split("/")[-1].replace("features_", "").replace(".csv", ""): load(p) for p in sys.argv[1:]}
names = list(sets)
cols = feats(sets[names[0]])

print("Held-out transfer. A good ruler puts healthy people at ~50th with ~5% in the top 5%.\n")

# Train on each dataset and test on each other dataset
for tr_name in names:
    for te_name in names:
        if tr_name == te_name:
            continue

        tr, te = sets[tr_name], sets[te_name]
        ytr, yte = tr["label"].values, te["label"].values
        print(f"train {tr_name} ({len(tr)}) -> test {te_name} ({len(te)})")

        # Test with pooled scaling
        Xtr, Xte = pooled_standardize(tr, te, cols)
        report("pooled", fit(Xtr, ytr), Xtr, ytr, Xte, yte)

        # Test with healthy scaling
        Xtr, Xte = healthy_standardize(tr, cols), healthy_standardize(te, cols)
        report("healthy", fit(Xtr, ytr), Xtr, ytr, Xte, yte)
        print()

# With exactly two datasets, also test a model trained on both together
if len(names) == 2:
    print("train BOTH (healthy-standardized), 5-fold over the pooled 112 - the shipping number")

    # Scale each dataset by its own healthy people and stack them together
    from sklearn.model_selection import StratifiedKFold
    a = healthy_standardize(sets[names[0]], cols)
    b = healthy_standardize(sets[names[1]], cols)
    X = np.vstack([a, b])
    y = np.concatenate([sets[names[0]]["label"].values, sets[names[1]]["label"].values])
    src = np.array([names[0]] * len(a) + [names[1]] * len(b))

    # Run 5 fold cross validation 30 times and keep the AUC of each run
    aucs = []
    for seed in range(30):
        prob = np.full(len(y), np.nan)
        for tr_i, te_i in StratifiedKFold(5, shuffle=True, random_state=seed).split(X, y):
            prob[te_i] = fit(X[tr_i], y[tr_i]).predict_proba(X[te_i])[:, 1]
        aucs.append(roc_auc_score(y, prob))

    # Print the median AUC with its 5th and 95th percentiles, then the AUC within each dataset from the last run
    print(f"  AUC {np.median(aucs):.3f}  [{np.percentile(aucs, 5):.3f}-{np.percentile(aucs, 95):.3f}]")
    for s in names:
        m = src == s
        print(f"    within {s:8s}: AUC {roc_auc_score(y[m], prob[m]):.3f}  (last repeat)")
