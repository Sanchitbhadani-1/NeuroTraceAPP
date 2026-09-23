"""How noisy is ONE drawing, and what does averaging three buy?

    python scripts/noise.py results/features_collected.csv

Needs the PER-TRIAL table. Nothing published has this - one drawing per person
everywhere - so this number is ours.
"""

import sys

import numpy as np
import pandas as pd
from scipy.stats import norm

META = {"subject_id", "label", "diagnosis", "source", "release", "task",
        "session", "trial", "age_bracket", "hand", "device", "fs_raw", "n_raw"}


# AUC -> separation, shrink the noise, back to AUC
def auc_after_averaging(auc_now, within_frac, k):

    d = norm.ppf(auc_now) * np.sqrt(2)

    shrink = np.sqrt((1 - within_frac) + within_frac / k)
    # Only the WITHIN-person part shrinks. Between-person differences stay

    return norm.cdf(d / shrink / np.sqrt(2))


df = pd.read_csv(sys.argv[1])
feats = [c for c in df.columns if c not in META and df[c].notna().mean() > 0.5]

grp = df.groupby(["subject_id", "session"])
multi = grp.filter(lambda g: len(g) >= 2)
if multi.empty:
    sys.exit("need 2+ trials per person-session to measure within-person noise")

print(f"{multi.groupby(['subject_id','session']).ngroups} person-sessions with 2+ trials, "
      f"{len(multi)} trials\n")
print(f"{'feature':28s} {'within SD':>10s} {'between SD':>11s} {'within %':>9s}   what 3 trials buy")

fracs = {}
for c in feats:
    g = multi.groupby(["subject_id", "session"])[c]

    within = np.sqrt(g.var(ddof=1).mean())
    # Same person, different trials - this is the noise

    between = g.mean().std(ddof=1)
    # Different people - this is the signal, and averaging cannot touch it

    total = within**2 + between**2
    frac = within**2 / total if total > 0 else np.nan
    fracs[c] = frac

    after = np.sqrt(between**2 + within**2 / 3)
    print(f"{c:28s} {within:10.4g} {between:11.4g} {100*frac:8.0f}%   spread shrinks {100*(1-after/np.sqrt(total)):.0f}%")

w = float(np.nanmedian(list(fracs.values())))
print(f"\nmedian within-person fraction across features: {100*w:.0f}%")
print("predicted AUC after averaging 3 trials (normal approximation):")
for now in (0.60, 0.72, 0.86):
    print(f"   {now:.2f} -> {auc_after_averaging(now, w, 3):.3f}")


# --- is the reference a fair ruler? ----------------------------------

healthy = df[df["diagnosis"] == "none"]
per_person = healthy.groupby("subject_id")[feats].mean()

if len(per_person) >= 10:
    print(f"\nleave-one-out: each of {len(per_person)} healthy people scored against the other "
          f"{len(per_person)-1} on every feature.")

    top5 = []
    for sid, row in per_person.iterrows():
        rest = per_person.drop(sid)
        pct = np.array([(rest[c] < row[c]).mean() * 100 for c in feats])
        top5.append((pct >= 95).mean())

    print(f"   fraction landing in the top 5%: {100*np.mean(top5):.1f}%   (5% = a fair ruler)")
    # This is the test the UCI reference FAILED on PaHaW - 83% instead of 5%
