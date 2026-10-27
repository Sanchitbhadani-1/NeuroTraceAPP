# DEGRADATION.PY REDRAWS EVERY SPIRAL AT EACH FIDELITY TIER AND CHECKS WHICH FEATURES AND MODEL SCORES HOLD UP
# RUN IT WITH PYTHONPATH=. python scripts/degradation.py ../data/UCI-395 results/degradation_uci.csv
# OR WITH PYTHONPATH=. python scripts/degradation.py <pahaw_root> results/degradation_pahaw.csv --pahaw <corpus_PaHaW.xlsx>

import argparse
import warnings

import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedGroupKFold

from neurotrace.datasets import iter_uci
from neurotrace.preprocess import clean, preprocess_trace
from neurotrace.features import extract_spiral_features
from neurotrace.synth import degrade, FIDELITY_TIERS


# The number of points per second the drawings are resampled to
FS = 100.0

# The C setting for the logistic regression, the same as in export_model.py
C = 0.05

# The rank match with the clean spiral a feature needs to count as holding up at a tier
HOLDS = 0.9


# RECORDS

# Give back each UCI spiral, marking only the hw_dataset ones as labelled
def uci_records(root):
    for rec in iter_uci(root):
        yield {"subject_id": rec["subject_id"], "label": rec["label"],
               "labelled": rec["subject_id"].split(":")[1] == "hw_dataset",
               "t": rec["t"], "x": rec["x"], "y": rec["y"], "fs": rec["fs"]}


# Give back each PaHaW spiral that has a label in the xlsx sheet
def pahaw_records(root, xlsx):
    from neurotrace.pahaw import iter_svc, load_svc, on_surface

    # Give each person a label of 1 if their diagnosis starts with P, or 0 if not
    meta = pd.read_excel(xlsx)
    labels = {int(s): int(str(v).strip().upper().startswith("P"))
              for s, v in zip(meta["ID"], meta["Disease"])}

    # Load each task 1 file, skip people with no label, and keep only the pen down points
    for path in iter_svc(root, task_id=1):
        rec = load_svc(path)
        if rec["subject"] not in labels:
            continue
        t, x, y = on_surface(rec)
        yield {"subject_id": f"pahaw:{rec['subject']:05d}", "label": labels[rec["subject"]],
               "labelled": True, "t": t, "x": x, "y": y, "fs": rate(t)}


# Find the points per second from the median time gap between points
def rate(t):
    dt = np.diff(t)
    return float(1.0 / np.median(dt[dt > 0]))


# Resample every spiral to the lowest points per second in the set
def match_rates(records):

    # If every spiral is within 1 point per second of the lowest, return them as they are
    fs0 = min(r["fs"] for r in records)
    if max(r["fs"] for r in records) - fs0 < 1.0:
        return records, None

    # Clean each spiral and fill in its x and y on an even grid at the lowest rate
    out = []
    for r in records:
        t, x, y = clean(r["t"], r["x"], r["y"])
        grid = np.arange(t[0], t[-1], 1.0 / fs0)
        out.append({**r, "t": grid, "x": np.interp(grid, t, x), "y": np.interp(grid, t, y), "fs": fs0})
    return out, fs0


# MEASURE

# Clean one spiral and measure its features, or give back an empty dict if it fails
def measure(t, x, y):

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            pt, px, py = preprocess_trace(t, x, y, fs=FS)
            return extract_spiral_features(pt, px, py, fs=FS)
    except ValueError:
        return {}


# Measure every spiral clean, then at each tier with each seed, into one table
def build(records, seeds):

    rows = []
    for i, r in enumerate(records):

        # Add a row for the clean spiral
        base = {"i": i, "subject_id": r["subject_id"], "label": r["label"], "labelled": r["labelled"]}
        rows.append({**base, "tier": "clean", "seed": 0, "fs": r["fs"], **measure(r["t"], r["x"], r["y"])})

        # Add a row for each tier and seed, with a different seed for each spiral and each repeat
        for tier, knobs in FIDELITY_TIERS.items():
            for s in range(seeds):
                t, x, y = degrade(r["t"], r["x"], r["y"], seed=1000 * i + s, **knobs)
                rows.append({**base, "tier": tier, "seed": s, "fs": rate(t), **measure(t, x, y)})

    return pd.DataFrame(rows)


# PER FEATURE

# For each tier and feature, find the rank match with the clean spiral, how far the average moves, and the failed share
def stability(df, cols):

    ref = df[df.tier == "clean"].set_index("i")[cols]
    out = []
    for tier in FIDELITY_TIERS:
        d = df[df.tier == tier]
        for c in cols:

            # For each seed, find the rank match and the move in the average in clean standard deviations
            rhos, shifts = [], []
            for _, g in d.groupby("seed"):
                a, b = ref[c], g.set_index("i")[c]
                ok = a.notna() & b.notna()
                rhos.append(spearmanr(a[ok], b[ok])[0])
                shifts.append((b[ok].mean() - a[ok].mean()) / a[ok].std())

            # Keep the medians over the seeds and the share of spirals that failed
            out.append({"tier": tier, "feature": c, "rho": np.nanmedian(rhos),
                        "shift_sd": np.nanmedian(shifts), "failed_pct": 100 * d[c].isna().mean()})
    return pd.DataFrame(out)


# Work out the AUC, or give back NaN if there are fewer than 5 values or only one label
def auc(y, v):
    ok = ~np.isnan(v)
    if ok.sum() < 5 or len(set(y[ok])) < 2:
        return np.nan
    return roc_auc_score(y[ok], v[ok])


# For each feature, find its AUC on the clean spirals and its median AUC at each tier
def feature_aucs(df, cols):

    lab = df[df.labelled]
    ref = lab[lab.tier == "clean"]
    out = []
    for c in cols:

        # Find the clean AUC and flip it to above 0.5 if it is below
        a0 = auc(ref.label.values, ref[c].values.astype(float))
        flip = a0 < 0.5
        out.append({"tier": "clean", "feature": c, "auc": 1 - a0 if flip else a0})

        # Find the AUC for each seed at each tier, flipped the same way as the clean one
        for tier in FIDELITY_TIERS:
            per_seed = [auc(g.label.values, g[c].values.astype(float))
                        for _, g in lab[lab.tier == tier].groupby("seed")]
            per_seed = [1 - a if flip else a for a in per_seed]
            out.append({"tier": tier, "feature": c, "auc": np.nanmedian(per_seed)})
    return pd.DataFrame(out)


# WHOLE MODEL

# Find the mean and standard deviation of the healthy rows, using 1 for any standard deviation of 0
def healthy_ruler(X, y):
    mu, sd = X[y == 0].mean(0), X[y == 0].std(0)
    sd[sd == 0] = 1.0
    return mu, sd


# Fill each missing value with the given median for its column
def fill(X, med):
    X = X.copy()
    r, c = np.nonzero(np.isnan(X))
    X[r, c] = med[c]
    return X


# Run cross validation and give back the AUCs of a model retrained on the tier and a model trained on clean data
def model_aucs(Xc, Xd, y, groups, repeats):

    lr = lambda: LogisticRegression(C=C, class_weight="balanced", max_iter=2000)
    retrained, shipped = [], []
    for rep in range(repeats):

        p_re, p_sh = np.full(len(y), np.nan), np.full(len(y), np.nan)
        for tr, te in StratifiedGroupKFold(5, shuffle=True, random_state=rep).split(Xc, y, groups):

            # Fill missing values with medians from the training rows only
            Ctr = fill(Xc[tr], np.nan_to_num(np.nanmedian(Xc[tr], 0)))
            med = np.nan_to_num(np.nanmedian(Xd[tr], 0))
            Dtr, Dte = fill(Xd[tr], med), fill(Xd[te], med)

            # Find the healthy mean and spread from the training rows, for the clean data and the tier data
            mu_c, sd_c = healthy_ruler(Ctr, y[tr])
            mu_d, sd_d = healthy_ruler(Dtr, y[tr])

            # Score the test rows with a model trained on clean data, then with one trained on the tier data
            p_sh[te] = lr().fit((Ctr - mu_c) / sd_c, y[tr]).predict_proba((Dte - mu_d) / sd_d)[:, 1]
            p_re[te] = lr().fit((Dtr - mu_d) / sd_d, y[tr]).predict_proba((Dte - mu_d) / sd_d)[:, 1]

        shipped.append(roc_auc_score(y, p_sh))
        retrained.append(roc_auc_score(y, p_re))

    return retrained, shipped


# Write the median with the 5th and 95th percentiles as text
def pct(a):
    lo, mid, hi = np.percentile(a, [5, 50, 95])
    return f"{mid:.3f} [{lo:.3f}-{hi:.3f}]"


# RUN

# Run the whole test, print the tables, and save the results
def main():

    # Read the command line settings and hide warnings
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--pahaw", metavar="XLSX", help="corpus_PaHaW.xlsx - run on your own machine only")
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--repeats", type=int, default=20)
    args = ap.parse_args()
    warnings.filterwarnings("ignore")

    # Load the spirals, match their rates, measure them all, and list the spiral features and tiers
    native = list(pahaw_records(args.root, args.pahaw) if args.pahaw else uci_records(args.root))
    records, fs0 = match_rates(native)
    df = build(records, args.seeds)
    cols = [c for c in df.columns if c.startswith("spiral_")]
    tiers = list(FIDELITY_TIERS)

    # Take the clean labelled rows in order as the training data and print the counts
    ids = df[(df.tier == "clean") & df.labelled].sort_values("i")
    order, y, groups = ids.i.values, ids.label.values, ids.subject_id.values
    Xc = ids[cols].values.astype(float)
    print(f"{len(records)} spirals, {len(y)} labelled ({(y == 0).sum()} healthy, {(y == 1).sum()} PD). "
          f"{args.seeds} noise seeds x {args.repeats} CV repeats per tier.")

    # If the rates were matched, print the lowest rank match between the matched and unmatched features
    if fs0:
        nat = pd.DataFrame([measure(r["t"], r["x"], r["y"]) for r in native])
        ref = df[df.tier == "clean"].reset_index(drop=True)
        worst = min(spearmanr(nat[c], ref[c], nan_policy="omit")[0] for c in cols)
        print(f"Every spiral rate-matched to {fs0:.1f} Hz first; rank agreement with the "
              f"unmatched features >= {worst:.3f} on every feature.")

    # Print the model table header
    print("\nMODEL  healthy-standardized logistic regression, C=0.05 (shipped recipe). AUC median [5th-95th]")
    print(f"  {'tier':9s} {'rate':>8s} {'failed':>7s}   {'retrained':24s}{'shipped':24s}")

    # For each tier, run the model test on every seed and print and keep the results
    model_rows = []
    for tier in ["clean", *tiers]:
        d = df[df.tier == tier]
        re_all, sh_all = [], []
        for _, g in d[d.labelled].groupby("seed"):
            Xd = g.set_index("i").loc[order, cols].values.astype(float)
            re, sh = model_aucs(Xc, Xd, y, groups, args.repeats)
            re_all += re
            sh_all += sh
        failed = 100 * d[cols].isna().all(axis=1).mean()
        print(f"  {tier:9s} {d.fs.median():6.1f}Hz {failed:6.1f}%   {pct(re_all):24s}"
              f"{pct(sh_all) if tier != 'clean' else '-':24s}")
        model_rows.append({"tier": tier, "rate_hz": d.fs.median(), "failed_pct": failed,
                           **{f"retrained_{k}": v for k, v in zip(("p5", "p50", "p95"), np.percentile(re_all, [5, 50, 95]))},
                           **{f"shipped_{k}": v for k, v in zip(("p5", "p50", "p95"), np.percentile(sh_all, [5, 50, 95]))}})

    # Work out the feature tables and print the feature table header
    st, au = stability(df, cols), feature_aucs(df, cols)
    print(f"\nFEATURES  rho = rank agreement with the clean spiral (all {len(records)}); AUC oriented, 0.5 = chance")
    print(f"  {'':28s}{'clean':>7s}" + "".join(f"{t:>15s}" for t in tiers) + "   survives")
    print(f"  {'feature':28s}{'AUC':>7s}" + "".join(f"{'rho   AUC':>15s}" for _ in tiers) + "   down to")

    # Print each feature's rank match and AUC at each tier
    for c in cols:
        cell = lambda tbl, t, k: tbl[(tbl.tier == t) & (tbl.feature == c)][k].item()
        line, survives, broke = "", "none", False

        # Find the last tier before the rank match first drops below HOLDS
        for t in tiers:
            rho = cell(st, t, "rho")
            line += f"{rho:>9.2f}{cell(au, t, 'auc'):>6.2f}"
            broke = broke or not rho >= HOLDS
            if not broke:
                survives = t
        print(f"  {c:28s}{cell(au, 'clean', 'auc'):>7.2f}{line}   {survives}")

    # Save the feature table and the model table
    res = au.merge(st, on=["tier", "feature"], how="left")
    res.to_csv(args.out, index=False)
    pd.DataFrame(model_rows).to_csv(args.out.replace(".csv", "_model.csv"), index=False)
    print(f"\n-> {args.out} and {args.out.replace('.csv', '_model.csv')}")


if __name__ == "__main__":
    main()
