"""Train on one dataset, test on the OTHER. The honest transfer test.

    PYTHONPATH=. python scripts/transfer.py results/features_uci395.csv results/features_pahaw.csv

Cross-validation inside one dataset shares the tablet, the template and the
room, so it cannot catch a model that learned the clinic. This can.

Two rulers, run side by side:
  pooled   - one scaler over the training set (the old way, and it FAILS)
  healthy  - each dataset standardized by ITS OWN healthy controls, so "+2"
             means "two healthy-SDs above normal" on every tablet
"""

import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}


def load(path):
    d = pd.read_csv(path)
    if "release" in d.columns and (d["release"] == "hw_dataset").any():
        d = d[d["release"] == "hw_dataset"]
    return d.reset_index(drop=True)


def feats(d):
    return [c for c in d.columns if c.startswith("spiral_")]


def healthy_standardize(d, cols):
    hc = d[d["label"] == 0][cols]
    mu, sd = hc.mean(), hc.std(ddof=0).replace(0, 1.0)
    return ((d[cols] - mu) / sd).values
    # The dataset's OWN healthy people are the ruler, not a pooled scaler


def pooled_standardize(train, test, cols):
    mu, sd = train[cols].mean(), train[cols].std(ddof=0).replace(0, 1.0)
    return ((train[cols] - mu) / sd).values, ((test[cols] - mu) / sd).values


def fit(X, y):
    return LogisticRegression(C=0.5, class_weight="balanced", max_iter=2000).fit(X, y)


def report(name, model, Xtr, ytr, Xte, yte):

    p_tr = model.predict_proba(Xtr)[:, 1]
    p_te = model.predict_proba(Xte)[:, 1]

    ref = np.sort(p_tr[ytr == 0])
    pct = np.array([100 * (ref < v).mean() for v in p_te])
    # The training set's healthy people are the reference, same as the app does

    hc, pd_ = pct[yte == 0], pct[yte == 1]
    auc = roc_auc_score(yte, p_te)
    bacc = balanced_accuracy_score(yte, p_te >= 0.5)

    print(f"  {name:8s}  AUC {auc:.3f}  bal.acc {bacc:.3f}   "
          f"test HEALTHY land at median {np.median(hc):3.0f}th pct, {100 * (hc >= 95).mean():3.0f}% in top 5%   "
          f"| test PATIENTS median {np.median(pd_):3.0f}th, {100 * (pd_ >= 95).mean():3.0f}% in top 5%")
    # THE PERCENTILES MATTER MORE THAN THE AUC. A bad AUC is useless; telling
    # healthy people they are in the top 5% is what the app would actually show


sets = {p.split("/")[-1].replace("features_", "").replace(".csv", ""): load(p) for p in sys.argv[1:]}
names = list(sets)
cols = feats(sets[names[0]])

print("Held-out transfer. A good ruler puts healthy people at ~50th with ~5% in the top 5%.\n")

for tr_name in names:
    for te_name in names:
        if tr_name == te_name:
            continue

        tr, te = sets[tr_name], sets[te_name]
        ytr, yte = tr["label"].values, te["label"].values
        print(f"train {tr_name} ({len(tr)}) -> test {te_name} ({len(te)})")

        Xtr, Xte = pooled_standardize(tr, te, cols)
        report("pooled", fit(Xtr, ytr), Xtr, ytr, Xte, yte)

        Xtr, Xte = healthy_standardize(tr, cols), healthy_standardize(te, cols)
        report("healthy", fit(Xtr, ytr), Xtr, ytr, Xte, yte)
        print()

if len(names) == 2:
    print("train BOTH (healthy-standardized), 5-fold over the pooled 112 - the shipping number")

    from sklearn.model_selection import StratifiedKFold
    a = healthy_standardize(sets[names[0]], cols)
    b = healthy_standardize(sets[names[1]], cols)
    X = np.vstack([a, b])
    y = np.concatenate([sets[names[0]]["label"].values, sets[names[1]]["label"].values])
    src = np.array([names[0]] * len(a) + [names[1]] * len(b))

    aucs = []
    for seed in range(30):
        prob = np.full(len(y), np.nan)
        for tr_i, te_i in StratifiedKFold(5, shuffle=True, random_state=seed).split(X, y):
            prob[te_i] = fit(X[tr_i], y[tr_i]).predict_proba(X[te_i])[:, 1]
        aucs.append(roc_auc_score(y, prob))

    print(f"  AUC {np.median(aucs):.3f}  [{np.percentile(aucs, 5):.3f}-{np.percentile(aucs, 95):.3f}]")
    for s in names:
        m = src == s
        print(f"    within {s:8s}: AUC {roc_auc_score(y[m], prob[m]):.3f}  (last repeat)")
    # With only TWO datasets, "train both hold one out" is the same as the rows
    # above. That changes the day a third dataset exists
