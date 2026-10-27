"""Degradation experiment: which features survive worse hardware.

    PYTHONPATH=. python scripts/degradation.py ../data/UCI-395 results/degradation_uci.csv
    PYTHONPATH=. python scripts/degradation.py <pahaw_root> results/degradation_pahaw.csv --pahaw <corpus_PaHaW.xlsx>

Every spiral is re-recorded at each FIDELITY_TIER with degrade(), then run
through the same preprocess + features as the app. Aggregate numbers only.
"""

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

FS = 100.0
C = 0.05
# Same C as export_model.py, so "shipped" is the model we actually ship

HOLDS = 0.9
# Rank agreement with the clean spiral needed to count as surviving a tier


# --- records ---------------------------------------------------------

def uci_records(root):
    for rec in iter_uci(root):
        yield {"subject_id": rec["subject_id"], "label": rec["label"],
               "labelled": rec["subject_id"].split(":")[1] == "hw_dataset",
               "t": rec["t"], "x": rec["x"], "y": rec["y"], "fs": rec["fs"]}
    # new_dataset has no controls - it counts for stability, not for AUC


def pahaw_records(root, xlsx):
    from neurotrace.pahaw import iter_svc, load_svc, on_surface

    meta = pd.read_excel(xlsx)
    labels = {int(s): int(str(v).strip().upper().startswith("P"))
              for s, v in zip(meta["ID"], meta["Disease"])}
    # Same label rule as extract_pahaw.py

    for path in iter_svc(root, task_id=1):
        rec = load_svc(path)
        if rec["subject"] not in labels:
            continue
        t, x, y = on_surface(rec)
        yield {"subject_id": f"pahaw:{rec['subject']:05d}", "label": labels[rec["subject"]],
               "labelled": True, "t": t, "x": x, "y": y, "fs": rate(t)}


def rate(t):
    dt = np.diff(t)
    return float(1.0 / np.median(dt[dt > 0]))


def match_rates(records):

    fs0 = min(r["fs"] for r in records)
    if max(r["fs"] for r in records) - fs0 < 1.0:
        return records, None
    # UCI: controls mostly 142.9 Hz, patients 111.1. degrade() skips whole
    # samples, so unmatched, the phone tier would give each group its own rate

    out = []
    for r in records:
        t, x, y = clean(r["t"], r["x"], r["y"])
        grid = np.arange(t[0], t[-1], 1.0 / fs0)
        out.append({**r, "t": grid, "x": np.interp(grid, t, x), "y": np.interp(grid, t, y), "fs": fs0})
    return out, fs0


# --- measure ---------------------------------------------------------

def measure(t, x, y):

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            pt, px, py = preprocess_trace(t, x, y, fs=FS)
            return extract_spiral_features(pt, px, py, fs=FS)
    except ValueError:
        return {}
    # A spiral too broken to measure is a failure to count, not a crash


def build(records, seeds):

    rows = []
    for i, r in enumerate(records):
        base = {"i": i, "subject_id": r["subject_id"], "label": r["label"], "labelled": r["labelled"]}
        rows.append({**base, "tier": "clean", "seed": 0, "fs": r["fs"], **measure(r["t"], r["x"], r["y"])})

        for tier, knobs in FIDELITY_TIERS.items():
            for s in range(seeds):
                t, x, y = degrade(r["t"], r["x"], r["y"], seed=1000 * i + s, **knobs)
                rows.append({**base, "tier": tier, "seed": s, "fs": rate(t), **measure(t, x, y)})
                # Seed per spiral AND per repeat, so no two spirals share noise

    return pd.DataFrame(rows)


# --- per feature -----------------------------------------------------

def stability(df, cols):

    ref = df[df.tier == "clean"].set_index("i")[cols]
    out = []
    for tier in FIDELITY_TIERS:
        d = df[df.tier == tier]
        for c in cols:
            rhos, shifts = [], []
            for _, g in d.groupby("seed"):
                a, b = ref[c], g.set_index("i")[c]
                ok = a.notna() & b.notna()
                rhos.append(spearmanr(a[ok], b[ok])[0])
                shifts.append((b[ok].mean() - a[ok].mean()) / a[ok].std())
            out.append({"tier": tier, "feature": c, "rho": np.nanmedian(rhos),
                        "shift_sd": np.nanmedian(shifts), "failed_pct": 100 * d[c].isna().mean()})
    return pd.DataFrame(out)
    # rho: does it still rank people the same. shift: how far the hardware moves
    # the level, in between-person SDs - the device's own reference absorbs that


def auc(y, v):
    ok = ~np.isnan(v)
    if ok.sum() < 5 or len(set(y[ok])) < 2:
        return np.nan
    return roc_auc_score(y[ok], v[ok])


def feature_aucs(df, cols):

    lab = df[df.labelled]
    ref = lab[lab.tier == "clean"]
    out = []
    for c in cols:
        a0 = auc(ref.label.values, ref[c].values.astype(float))
        flip = a0 < 0.5
        # Oriented to the clean direction, so a feature that flips drops below 0.5
        out.append({"tier": "clean", "feature": c, "auc": 1 - a0 if flip else a0})
        for tier in FIDELITY_TIERS:
            per_seed = [auc(g.label.values, g[c].values.astype(float))
                        for _, g in lab[lab.tier == tier].groupby("seed")]
            per_seed = [1 - a if flip else a for a in per_seed]
            out.append({"tier": tier, "feature": c, "auc": np.nanmedian(per_seed)})
    return pd.DataFrame(out)


# --- whole model -----------------------------------------------------

def healthy_ruler(X, y):
    mu, sd = X[y == 0].mean(0), X[y == 0].std(0)
    sd[sd == 0] = 1.0
    return mu, sd
    # Same fix as export_model.py: the hardware's own healthy people are its ruler


def fill(X, med):
    X = X.copy()
    r, c = np.nonzero(np.isnan(X))
    X[r, c] = med[c]
    return X
    # Median from the TRAINING rows only, like the imputer in evaluate.py


def model_aucs(Xc, Xd, y, groups, repeats):

    lr = lambda: LogisticRegression(C=C, class_weight="balanced", max_iter=2000)
    retrained, shipped = [], []
    for rep in range(repeats):

        p_re, p_sh = np.full(len(y), np.nan), np.full(len(y), np.nan)
        for tr, te in StratifiedGroupKFold(5, shuffle=True, random_state=rep).split(Xc, y, groups):

            Ctr = fill(Xc[tr], np.nan_to_num(np.nanmedian(Xc[tr], 0)))
            med = np.nan_to_num(np.nanmedian(Xd[tr], 0))
            Dtr, Dte = fill(Xd[tr], med), fill(Xd[te], med)

            mu_c, sd_c = healthy_ruler(Ctr, y[tr])
            mu_d, sd_d = healthy_ruler(Dtr, y[tr])
            # Test people are measured against the TRAINING fold's healthy people
            # on the same hardware - the reference the app would collect there

            p_sh[te] = lr().fit((Ctr - mu_c) / sd_c, y[tr]).predict_proba((Dte - mu_d) / sd_d)[:, 1]
            p_re[te] = lr().fit((Dtr - mu_d) / sd_d, y[tr]).predict_proba((Dte - mu_d) / sd_d)[:, 1]
            # shipped: weights learned on clean data, like the app
            # retrained: weights learned on this hardware - is the signal still there

        shipped.append(roc_auc_score(y, p_sh))
        retrained.append(roc_auc_score(y, p_re))

    return retrained, shipped


def pct(a):
    lo, mid, hi = np.percentile(a, [5, 50, 95])
    return f"{mid:.3f} [{lo:.3f}-{hi:.3f}]"


# --- run -------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--pahaw", metavar="XLSX", help="corpus_PaHaW.xlsx - run on your own machine only")
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--repeats", type=int, default=20)
    args = ap.parse_args()
    warnings.filterwarnings("ignore")

    native = list(pahaw_records(args.root, args.pahaw) if args.pahaw else uci_records(args.root))
    records, fs0 = match_rates(native)
    df = build(records, args.seeds)
    cols = [c for c in df.columns if c.startswith("spiral_")]
    tiers = list(FIDELITY_TIERS)

    ids = df[(df.tier == "clean") & df.labelled].sort_values("i")
    order, y, groups = ids.i.values, ids.label.values, ids.subject_id.values
    Xc = ids[cols].values.astype(float)
    print(f"{len(records)} spirals, {len(y)} labelled ({(y == 0).sum()} healthy, {(y == 1).sum()} PD). "
          f"{args.seeds} noise seeds x {args.repeats} CV repeats per tier.")

    if fs0:
        nat = pd.DataFrame([measure(r["t"], r["x"], r["y"]) for r in native])
        ref = df[df.tier == "clean"].reset_index(drop=True)
        worst = min(spearmanr(nat[c], ref[c], nan_policy="omit")[0] for c in cols)
        print(f"Every spiral rate-matched to {fs0:.1f} Hz first; rank agreement with the "
              f"unmatched features >= {worst:.3f} on every feature.")

    print("\nMODEL  healthy-standardized logistic regression, C=0.05 (shipped recipe). AUC median [5th-95th]")
    print(f"  {'tier':9s} {'rate':>8s} {'failed':>7s}   {'retrained':24s}{'shipped':24s}")
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

    st, au = stability(df, cols), feature_aucs(df, cols)
    print(f"\nFEATURES  rho = rank agreement with the clean spiral (all {len(records)}); AUC oriented, 0.5 = chance")
    print(f"  {'':28s}{'clean':>7s}" + "".join(f"{t:>15s}" for t in tiers) + "   survives")
    print(f"  {'feature':28s}{'AUC':>7s}" + "".join(f"{'rho   AUC':>15s}" for _ in tiers) + "   down to")
    for c in cols:
        cell = lambda tbl, t, k: tbl[(tbl.tier == t) & (tbl.feature == c)][k].item()
        line, survives, broke = "", "none", False
        for t in tiers:
            rho = cell(st, t, "rho")
            line += f"{rho:>9.2f}{cell(au, t, 'auc'):>6.2f}"
            broke = broke or not rho >= HOLDS
            if not broke:
                survives = t
        # The worst tier it reaches with every better tier holding too
        print(f"  {c:28s}{cell(au, 'clean', 'auc'):>7.2f}{line}   {survives}")

    res = au.merge(st, on=["tier", "feature"], how="left")
    res.to_csv(args.out, index=False)
    pd.DataFrame(model_rows).to_csv(args.out.replace(".csv", "_model.csv"), index=False)
    print(f"\n-> {args.out} and {args.out.replace('.csv', '_model.csv')}")


if __name__ == "__main__":
    main()
