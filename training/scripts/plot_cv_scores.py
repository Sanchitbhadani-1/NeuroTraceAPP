# PLOT_CV_SCORES.PY PLOTS THE SCORE THE MODEL GIVES EACH PERSON WHILE THAT PERSON IS HELD OUT
# IT PRINTS THE AUC WITH SCALING DONE INSIDE EACH FOLD AND WITH SCALING DONE BEFORE SPLITTING
# RUN IT WITH PYTHONPATH=. python scripts/plot_cv_scores.py results/features_uci395.csv results/features_pahaw.csv [--C 0.05] [--repeats 30] [--leaky] [--out cv_scores.png]

import argparse
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, balanced_accuracy_score
from sklearn.model_selection import StratifiedGroupKFold

# Draw the plots to a file with no window
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Let Python find the other files in scripts/
sys.path.insert(0, "scripts")

# Use the same row loading as export_model.py
from export_model import load_training


# The colors for healthy dots, patient dots, main text, light text, and grid lines
HEALTHY = "#0066cc"
PATIENT = "#a65200"
INK = "#1d1d1f"
INK2 = "#6e6e73"
GRID = "#d2d2d7"


# SCORING

# Train a logistic regression model
def fit(X, y, C):
    return LogisticRegression(C=C, class_weight="balanced", max_iter=2000).fit(X, y)


# Find the mean and standard deviation of the healthy people among the given rows only
def healthy_scale(raw, label, rows, cols):
    hc = raw.loc[rows & (label == 0), cols]

    # If there are no healthy people in the rows, use everyone in the rows
    if len(hc) == 0:
        hc = raw.loc[rows, cols]
    return hc.mean(), hc.std(ddof=0).replace(0, 1.0)


# Score each person with a model trained without them, for one split
def out_of_fold(raw, label, groups, src, cols, C, seed, leaky):

    prob = np.full(len(label), np.nan)
    splitter = StratifiedGroupKFold(5, shuffle=True, random_state=seed)

    # Leaky version, scale each dataset by all its healthy people before splitting
    if leaky:
        X = np.vstack([
            ((raw.loc[src == s, cols] - healthy_scale(raw, label, src == s, cols)[0])
             / healthy_scale(raw, label, src == s, cols)[1]).values
            for s in pd.unique(src)
        ])

        # Put the stacked rows back in their original order
        order = np.concatenate([np.where(src == s)[0] for s in pd.unique(src)])
        Xl = np.empty_like(X)
        Xl[order] = X

        # Train on each training part and score the held out part
        for tr, te in splitter.split(Xl, label, groups):
            prob[te] = fit(Xl[tr], label[tr], C).predict_proba(Xl[te])[:, 1]
        return prob

    # Inside fold version, go through each split
    for tr, te in splitter.split(raw[cols].values, label, groups):

        # Mark which rows are in the training part
        is_train = np.zeros(len(label), dtype=bool)
        is_train[tr] = True

        # Scale each dataset by the healthy people in its training part only
        X = np.empty((len(label), len(cols)))
        for s in pd.unique(src):
            here = src == s
            mu, sd = healthy_scale(raw, label, here & is_train, cols)
            X[here] = ((raw.loc[here, cols] - mu) / sd).values

        # Train on the training part and score the held out part
        prob[te] = fit(X[tr], label[tr], C).predict_proba(X[te])[:, 1]

    return prob


# PLOT

# Draw one dot per person at their held out score, in a healthy row and a Parkinson's row, and save the picture
def plot(prob, label, auc_lo, auc, auc_hi, bacc, repeats, out):

    rng = np.random.default_rng(0)
    fig, ax = plt.subplots(figsize=(10, 4.4))

    # Draw the healthy row, then the Parkinson's row
    for row, (mask, name, color) in enumerate((
        (label == 0, "Healthy", HEALTHY),
        (label == 1, "Parkinson's", PATIENT),
    )):

        # Move each dot up or down by a small random amount
        v = prob[mask]
        y = row + rng.uniform(-0.17, 0.17, len(v))

        # Draw the dots with a white ring around each one
        ax.plot(v, y, "o", ms=8, color=color, alpha=0.75,
                markeredgecolor="white", markeredgewidth=1.2, linestyle="none")

        # Draw a line at the median score
        med = np.median(v)
        ax.plot([med] * 2, [row - 0.32, row + 0.32], "-", color=color, lw=2.5)

        # Write the median next to its line, on the side away from 0.5
        left = med < 0.5
        ax.annotate(f"median {med:.2f}", (med + (-0.012 if left else 0.012), row + 0.32),
                    color=color, fontsize=10, ha="right" if left else "left", va="center")

    # Draw a dashed line at 0.5 and label it
    ax.axvline(0.5, color=INK2, lw=1.2, ls=(0, (5, 4)), alpha=0.7, zorder=0)
    ax.annotate("0.5", (0.512, -0.62), color=INK2, fontsize=9, ha="left")

    # Name the two rows on the y axis
    ax.set_yticks([0, 1], ["Healthy", "Parkinson's"], fontsize=12, color=INK)

    # Set the axis limits and x label, with Healthy on top
    ax.set_ylim(-0.7, 1.7)
    ax.set_xlim(-0.02, 1.02)
    ax.set_xlabel("Model score when this person was held out (dots from one split)", fontsize=11, color=INK2)
    ax.invert_yaxis()

    # Write the AUC as the title, and the count, AUC range over splits, and balanced accuracy under it
    ax.set_title(f"AUC {auc:.2f}", fontsize=22, color=INK, loc="left", pad=22, fontweight="bold")
    ax.annotate(f"{len(prob)} people   ·   {auc_lo:.2f} to {auc_hi:.2f} across {repeats} repeated splits"
                f"   ·   balanced accuracy {bacc:.0%}   ·   a coin flip is 0.50",
                xy=(0, 1.04), xycoords="axes fraction", fontsize=10.5, color=INK2)

    # Draw light grid lines behind the dots, hide the top, right and left edges, and hide the tick marks
    ax.grid(axis="x", color=GRID, lw=0.6, alpha=0.6)
    ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=INK2, length=0)

    # Save the picture
    fig.tight_layout()
    fig.savefig(out, dpi=220, facecolor="white")
    print(f"wrote {out}")


# MAIN

# Score everyone both ways, print the AUCs, and plot one of them
def main():

    # Read the command line settings and check the seed is one of the splits that get run
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

    # Load each training table, named after its file
    sets = {p.split("/")[-1].replace("features_", "").replace(".csv", ""): load_training(p)
            for p in args.training}

    # Join the tables and pull out the features, labels, people, and dataset names
    raw = pd.concat(sets.values(), ignore_index=True)
    cols = [c for c in raw.columns if c.startswith("spiral_")]
    label = raw["label"].values
    groups = raw["subject_id"].values
    src = np.concatenate([[name] * len(d) for name, d in sets.items()])

    print(f"{len(raw)} people: {(label == 0).sum()} healthy, {(label == 1).sum()} with Parkinson's, "
          f"{len(cols)} measures, C={args.C}, {args.repeats} splits")

    # Run every split and give back the AUC percentiles, the median balanced accuracy, and the scores from the chosen split
    def run(leaky):
        aucs, baccs, probs = [], [], []
        for seed in range(args.repeats):
            p = out_of_fold(raw, label, groups, src, cols, args.C, seed, leaky)
            aucs.append(roc_auc_score(label, p))
            baccs.append(balanced_accuracy_score(label, p >= 0.5))
            probs.append(p)
        lo, mid, hi = np.percentile(aucs, [5, 50, 95])
        return lo, mid, hi, float(np.median(baccs)), probs[args.seed]

    # Run both versions on the same splits
    honest = run(False)
    leaky = run(True)

    # Print both AUCs, the difference between them, and the line for Copy.MODEL_AUC
    for name, (lo, mid, hi, bacc, _) in (("scaled inside each fold", honest), ("scaled before splitting", leaky)):
        print(f"  {name}  AUC {mid:.3f} [{lo:.3f}-{hi:.3f}]   balanced accuracy {bacc:.3f}")
    print(f"  the leak adds {leaky[1] - honest[1]:+.3f}")
    print(f"\nCopy.MODEL_AUC = {honest[1]:.2f}      say: an honest AUC of {honest[1]:.2f}")

    # Plot the leaky version if --leaky is given, or else the inside fold version
    lo, mid, hi, bacc, shown = leaky if args.leaky else honest
    plot(shown, label, lo, mid, hi, bacc, args.repeats, args.out)


if __name__ == "__main__":
    main()
