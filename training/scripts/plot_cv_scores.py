"""Plot the score the model gives each person when that person was held out.

    PYTHONPATH=. python scripts/plot_cv_scores.py results/features_uci395.csv results/features_pahaw.csv \
        [--C 0.05] [--repeats 30] [--leaky] [--out cv_scores.png]

The chart for the video. One dot per person, at the score the model gave them
while they were in the held-out fold, so no dot comes from a model that had
already seen that person.

Every run prints the AUC two ways, on the same splits:
  scaled inside each fold  - the healthy ruler is built from the training half only. The honest number
  scaled before splitting  - what export_model.py does. The held-out people help set their own ruler,
                             a small leak that flatters the score
and the line to paste into Copy.MODEL_AUC. The chart shows the honest one; --leaky plots the other.
"""

import argparse
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score
from sklearn.model_selection import StratifiedGroupKFold

import matplotlib
matplotlib.use("Agg")
# No window on a headless run, and the file is what the slide needs anyway
import matplotlib.pyplot as plt

sys.path.insert(0, "scripts")

from export_model import load_training
# The exact same row filtering as the shipping model, or this plots a different
# population from the one the app ships


# Both from the app's own accent list, so the slide matches the app.
# Checked for color-blind separation, not picked by eye
HEALTHY = "#0066cc"
PATIENT = "#a65200"
INK = "#1d1d1f"
INK2 = "#6e6e73"
GRID = "#d2d2d7"


# --- scoring ---------------------------------------------------------

def fit(X, y, C):
    return LogisticRegression(C=C, class_weight="balanced", max_iter=2000).fit(X, y)


def healthy_scale(raw, label, rows, cols):
    """mean and sd of the healthy people among `rows` only."""
    hc = raw.loc[rows & (label == 0), cols]
    if len(hc) == 0:
        hc = raw.loc[rows, cols]
        # No healthy people from this dataset landed in this half - fall back to
        # everyone in it rather than returning a column of NaN
    return hc.mean(), hc.std(ddof=0).replace(0, 1.0)


def out_of_fold(raw, label, groups, src, cols, C, seed, leaky):

    prob = np.full(len(label), np.nan)
    splitter = StratifiedGroupKFold(5, shuffle=True, random_state=seed)

    if leaky:
        X = np.vstack([
            ((raw.loc[src == s, cols] - healthy_scale(raw, label, src == s, cols)[0])
             / healthy_scale(raw, label, src == s, cols)[1]).values
            for s in pd.unique(src)
        ])
        order = np.concatenate([np.where(src == s)[0] for s in pd.unique(src)])
        Xl = np.empty_like(X)
        Xl[order] = X
        # vstack put the datasets back-to-back, so undo that before indexing by fold

        for tr, te in splitter.split(Xl, label, groups):
            prob[te] = fit(Xl[tr], label[tr], C).predict_proba(Xl[te])[:, 1]
        return prob

    for tr, te in splitter.split(raw[cols].values, label, groups):

        is_train = np.zeros(len(label), dtype=bool)
        is_train[tr] = True

        X = np.empty((len(label), len(cols)))
        for s in pd.unique(src):
            here = src == s
            mu, sd = healthy_scale(raw, label, here & is_train, cols)
            X[here] = ((raw.loc[here, cols] - mu) / sd).values
            # Each dataset keeps its own ruler - that is what makes a "+2" mean
            # the same thing on a different tablet - but the ruler is now built
            # from training people only

        prob[te] = fit(X[tr], label[tr], C).predict_proba(X[te])[:, 1]

    return prob


# --- plot ------------------------------------------------------------

def plot(prob, label, auc_lo, auc, auc_hi, bacc, repeats, out):

    rng = np.random.default_rng(0)
    fig, ax = plt.subplots(figsize=(10, 4.4))

    for row, (mask, name, color) in enumerate((
        (label == 0, "Healthy", HEALTHY),
        (label == 1, "Parkinson's", PATIENT),
    )):
        v = prob[mask]
        y = row + rng.uniform(-0.17, 0.17, len(v))
        # Jitter only, never a second meaning - the vertical position says nothing

        ax.plot(v, y, "o", ms=8, color=color, alpha=0.75,
                markeredgecolor="white", markeredgewidth=1.2, linestyle="none")
        # A white ring so overlapping people stay countable

        med = np.median(v)
        ax.plot([med] * 2, [row - 0.32, row + 0.32], "-", color=color, lw=2.5)
        left = med < 0.5
        ax.annotate(f"median {med:.2f}", (med + (-0.012 if left else 0.012), row + 0.32),
                    color=color, fontsize=10, ha="right" if left else "left", va="center")
        # Beside the tick, on the side away from the 0.5 line, so neither the tick
        # nor the threshold strikes through the words

    ax.axvline(0.5, color=INK2, lw=1.2, ls=(0, (5, 4)), alpha=0.7, zorder=0)
    ax.annotate("0.5", (0.512, -0.62), color=INK2, fontsize=9, ha="left")
    # Dashed and darker than the grid, because this one is a threshold and the
    # gridlines are only furniture

    ax.set_yticks([0, 1], ["Healthy", "Parkinson's"], fontsize=12, color=INK)
    # The group name is on the axis, so the color is never the only label

    ax.set_ylim(-0.7, 1.7)
    ax.set_xlim(-0.02, 1.02)
    ax.set_xlabel("Model score when this person was held out (dots from one split)", fontsize=11, color=INK2)
    ax.invert_yaxis()

    ax.set_title(f"AUC {auc:.2f}", fontsize=22, color=INK, loc="left", pad=22, fontweight="bold")
    ax.annotate(f"{len(prob)} people   ·   {auc_lo:.2f} to {auc_hi:.2f} across {repeats} repeated splits"
                f"   ·   balanced accuracy {bacc:.0%}   ·   a coin flip is 0.50",
                xy=(0, 1.04), xycoords="axes fraction", fontsize=10.5, color=INK2)
    # The range is the AUC's 5th to 95th percentile over different random splits - how much the
    # number moves depending on who lands in which fold, not a range over people

    ax.grid(axis="x", color=GRID, lw=0.6, alpha=0.6)
    ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=INK2, length=0)

    fig.tight_layout()
    fig.savefig(out, dpi=220, facecolor="white")
    print(f"wrote {out}")


# --- main ------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("training", nargs="+", help="feature CSVs with patients AND controls")
    ap.add_argument("--C", type=float, default=0.05)
    ap.add_argument("--repeats", type=int, default=30, help="splits to average the AUC over")
    ap.add_argument("--seed", type=int, default=0, help="the split the dots come from")
    ap.add_argument("--leaky", action="store_true", help="plot the pre-split-scaling version (both are always printed)")
    ap.add_argument("--out", default="cv_scores.png")
    args = ap.parse_args()
    if not 0 <= args.seed < args.repeats:
        ap.error(f"--seed must be between 0 and {args.repeats - 1}, the splits that get run")

    sets = {p.split("/")[-1].replace("features_", "").replace(".csv", ""): load_training(p)
            for p in args.training}

    raw = pd.concat(sets.values(), ignore_index=True)
    cols = [c for c in raw.columns if c.startswith("spiral_")]
    label = raw["label"].values
    groups = raw["subject_id"].values
    src = np.concatenate([[name] * len(d) for name, d in sets.items()])

    print(f"{len(raw)} people: {(label == 0).sum()} healthy, {(label == 1).sum()} with Parkinson's, "
          f"{len(cols)} measures, C={args.C}, {args.repeats} splits")

    def run(leaky):
        aucs, baccs, probs = [], [], []
        for seed in range(args.repeats):
            p = out_of_fold(raw, label, groups, src, cols, args.C, seed, leaky)
            aucs.append(roc_auc_score(label, p))
            baccs.append(balanced_accuracy_score(label, p >= 0.5))
            probs.append(p)
        lo, mid, hi = np.percentile(aucs, [5, 50, 95])
        return lo, mid, hi, float(np.median(baccs)), probs[args.seed]
        # The dots come from one split; the range in the subtitle comes from all of them

    honest = run(False)
    leaky = run(True)
    # Same seeds, so same folds - the only difference between the two is when the ruler gets built

    for name, (lo, mid, hi, bacc, _) in (("scaled inside each fold", honest), ("scaled before splitting", leaky)):
        print(f"  {name}  AUC {mid:.3f} [{lo:.3f}-{hi:.3f}]   balanced accuracy {bacc:.3f}")
    print(f"  the leak adds {leaky[1] - honest[1]:+.3f}")
    print(f"\nCopy.MODEL_AUC = {honest[1]:.2f}      say: an honest AUC of {honest[1]:.2f}")

    lo, mid, hi, bacc, shown = leaky if args.leaky else honest
    plot(shown, label, lo, mid, hi, bacc, args.repeats, args.out)


if __name__ == "__main__":
    main()
