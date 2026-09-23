"""Every PaHaW recording of one task into one feature CSV.

    PYTHONPATH=. python scripts/extract_pahaw.py <pahaw_root> <corpus_PaHaW.xlsx> <out.csv> [task]

task 1 is the spiral (default), 2 is a row of cursive l's.
Same columns as features_uci395.csv, so evaluate.py runs on either.
Aggregate numbers only - no coordinate rows leave the machine.
"""

import sys
import warnings

import numpy as np
import pandas as pd

from neurotrace.pahaw import iter_svc, load_svc, on_surface
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features, extract_writing_features
from neurotrace.extra import pressure_features, in_air_features

FS = 100.0
ID_COL = "ID"
LABEL_COL = "Disease"

TASK = int(sys.argv[4]) if len(sys.argv) > 4 else 1

EXTRACT = {1: extract_spiral_features, 2: extract_writing_features}[TASK]
TASK_NAME = {1: "spiral", 2: "writing"}[TASK]
# Look the function up in a dict instead of an if/else - adding task 3 is one line

Y_UP = True
# PaHaW's y grows UPWARD like graph paper. Checked by plotting subject 4's l's

root, xlsx, out = sys.argv[1], sys.argv[2], sys.argv[3]


# --- labels ----------------------------------------------------------

meta = pd.read_excel(xlsx)

print("xlsx columns:", list(meta.columns))
if ID_COL not in meta.columns or LABEL_COL not in meta.columns:
    sys.exit("edit ID_COL / LABEL_COL at the top to match the columns above")
# Print first, bail loudly - the column names were a guess

labels = {}
for sid, val in zip(meta[ID_COL], meta[LABEL_COL]):
    labels[int(sid)] = int(str(val).strip().upper().startswith("P"))
# 'PD' -> 1, 'H' -> 0. str/strip/upper so pd, PD and " PD " all work


# --- extract ---------------------------------------------------------

rows, skipped = [], []
for path in iter_svc(root, task_id=TASK):
    rec = load_svc(path)

    if rec["subject"] not in labels:
        skipped.append((path.name, "no label in xlsx"))
        continue

    t, x, y = on_surface(rec)

    fs_raw = 1.0 / np.median(np.diff(t)[np.diff(t) > 0])
    # Median gap, so pen lifts do not drag it down. The plot's crude version
    # said 102 Hz; this says the true 125

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            pt, px, py = preprocess_trace(t, x, y if Y_UP else -y, fs=FS)
            f = EXTRACT(pt, px, py, fs=FS)
    except ValueError as e:
        skipped.append((path.name, str(e)))
        continue
    # Library is strict, batch job is tolerant and says what it skipped

    rows.append({
        "subject_id": f"pahaw:{rec['subject']:05d}",
        # Prefixed so it can never collide with a uci: id when tables are stacked

        "label": labels[rec["subject"]],
        "source": "pahaw",
        "release": "pahaw",
        "task": TASK_NAME,
        "fs_raw": fs_raw,
        "n_raw": len(t),

        **f,

        **pressure_features(t, rec["pressure"][rec["pen_down"]]),
        # On-surface only - in-air pressure is 0 by definition

        **in_air_features(rec["t"], rec["pen_down"]),
        # The FULL recording, lifts included - that is the whole point
    })

df = pd.DataFrame(rows)
df.to_csv(out, index=False)

for name, why in skipped:
    print(f"  SKIPPED {name}: {why}")
print(f"{len(df)} rows -> {out}")
print(df.groupby("label").size().rename({0: "healthy", 1: "patient"}))
print(f"fs_raw: median {df.fs_raw.median():.1f} Hz, range {df.fs_raw.min():.1f}-{df.fs_raw.max():.1f}")
