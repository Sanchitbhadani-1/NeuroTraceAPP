# NOISE.PY MEASURES HOW MUCH EACH FEATURE CHANGES BETWEEN ONE PERSON'S TRIALS AND BETWEEN PEOPLE
# IT PREDICTS THE AUC AFTER AVERAGING 3 TRIALS AND TESTS THE HEALTHY REFERENCE ONE PERSON AT A TIME
# RUN IT WITH python scripts/noise.py results/features_collected.csv

import sys

import numpy as np
import pandas as pd
from scipy.stats import norm


# The columns that are not features
META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}


# Predict the AUC after averaging k trials, from the AUC now and the share of spread within each person
def auc_after_averaging(auc_now, within_frac, k):

    # Turn the AUC into a distance between the two groups
    d = norm.ppf(auc_now) * np.sqrt(2)

    # Shrink only the within person part of the spread by k
    shrink = np.sqrt((1 - within_frac) + within_frac / k)

    # Turn the new distance back into an AUC
    return norm.cdf(d / shrink / np.sqrt(2))


# Read the trial table and keep the features that have a value in more than half the rows
df = pd.read_csv(sys.argv[1])
feats = [c for c in df.columns if c not in META and df[c].notna().mean() > 0.5]

# Keep only the person sessions with at least 2 trials, or stop if there are none
grp = df.groupby(["subject_id", "session"])
multi = grp.filter(lambda g: len(g) >= 2)
if multi.empty:
    sys.exit("need 2+ trials per person-session to measure within-person noise")

# Print the counts and the table header
print(f"{multi.groupby(['subject_id','session']).ngroups} person-sessions with 2+ trials, "
      f"{len(multi)} trials\n")
print(f"{'feature':28s} {'within SD':>10s} {'between SD':>11s} {'within %':>9s}   what 3 trials buy")

# Measure the spread of each feature
fracs = {}
for c in feats:
    g = multi.groupby(["subject_id", "session"])[c]

    # The spread between trials of the same person
    within = np.sqrt(g.var(ddof=1).mean())

    # The spread between each person's average
    between = g.mean().std(ddof=1)

    # Find the share of the total spread that is within each person
    total = within**2 + between**2
    frac = within**2 / total if total > 0 else np.nan
    fracs[c] = frac

    # Find the spread after averaging 3 trials and print how much it shrinks
    after = np.sqrt(between**2 + within**2 / 3)
    print(f"{c:28s} {within:10.4g} {between:11.4g} {100*frac:8.0f}%   spread shrinks {100*(1-after/np.sqrt(total)):.0f}%")

# Print the median within person share and the predicted AUC after averaging 3 trials for a few starting AUCs
w = float(np.nanmedian(list(fracs.values())))
print(f"\nmedian within-person fraction across features: {100*w:.0f}%")
print("predicted AUC after averaging 3 trials (normal approximation):")
for now in (0.60, 0.72, 0.86):
    print(f"   {now:.2f} -> {auc_after_averaging(now, w, 3):.3f}")


# CHECK THE HEALTHY REFERENCE

# Average each healthy person's features
healthy = df[df["diagnosis"] == "none"]
per_person = healthy.groupby("subject_id")[feats].mean()

# Run the check only with at least 10 healthy people
if len(per_person) >= 10:
    print(f"\nleave-one-out: each of {len(per_person)} healthy people scored against the other "
          f"{len(per_person)-1} on every feature.")

    # Score each healthy person against everyone else and find the share of features in the top 5%
    top5 = []
    for sid, row in per_person.iterrows():
        rest = per_person.drop(sid)
        pct = np.array([(rest[c] < row[c]).mean() * 100 for c in feats])
        top5.append((pct >= 95).mean())

    # Print the average share that lands in the top 5%
    print(f"   fraction landing in the top 5%: {100*np.mean(top5):.1f}%   (5% = a fair ruler)")
