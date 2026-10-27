# EXTRACT_PAHAW.PY MEASURES EVERY PAHAW RECORDING OF ONE TASK AND SAVES THE FEATURES IN ONE CSV
# TASK 1 IS THE SPIRAL AND IS USED IF NO TASK IS GIVEN, TASK 2 IS A ROW OF CURSIVE L'S
# RUN IT WITH PYTHONPATH=. python scripts/extract_pahaw.py <pahaw_root> <corpus_PaHaW.xlsx> <out.csv> [task]

import sys
import warnings

import numpy as np
import pandas as pd

from neurotrace.pahaw import iter_svc, load_svc, on_surface
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features, extract_writing_features
from neurotrace.extra import pressure_features, in_air_features


# The number of points per second the drawings are resampled to
FS = 100.0

# The names of the ID and diagnosis columns in the xlsx sheet
ID_COL = "ID"
LABEL_COL = "Disease"

# The task number from the command line, or 1 if none is given
TASK = int(sys.argv[4]) if len(sys.argv) > 4 else 1

# Pick the feature function and task name for the task number
EXTRACT = {1: extract_spiral_features, 2: extract_writing_features}[TASK]
TASK_NAME = {1: "spiral", 2: "writing"}[TASK]

# Whether y grows upward in the PaHaW files
Y_UP = True

# Read the data folder, the xlsx sheet, and the output file
root, xlsx, out = sys.argv[1], sys.argv[2], sys.argv[3]


# LABELS

# Read the xlsx sheet and print its column names
meta = pd.read_excel(xlsx)
print("xlsx columns:", list(meta.columns))

# Stop if the ID or diagnosis column is missing
if ID_COL not in meta.columns or LABEL_COL not in meta.columns:
    sys.exit("edit ID_COL / LABEL_COL at the top to match the columns above")

# Give each person a label of 1 if their diagnosis starts with P, or 0 if not
labels = {}
for sid, val in zip(meta[ID_COL], meta[LABEL_COL]):
    labels[int(sid)] = int(str(val).strip().upper().startswith("P"))


# EXTRACT

# Go through every recording of the task
rows, skipped = [], []
for path in iter_svc(root, task_id=TASK):
    rec = load_svc(path)

    # Skip the recording if the person has no label
    if rec["subject"] not in labels:
        skipped.append((path.name, "no label in xlsx"))
        continue

    # Keep only the points where the pen touches the tablet
    t, x, y = on_surface(rec)

    # Find the raw points per second from the median time gap between points
    fs_raw = 1.0 / np.median(np.diff(t)[np.diff(t) > 0])

    # Clean the drawing and measure its features, or note it and move on if it fails
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            pt, px, py = preprocess_trace(t, x, y if Y_UP else -y, fs=FS)
            f = EXTRACT(pt, px, py, fs=FS)
    except ValueError as e:
        skipped.append((path.name, str(e)))
        continue

    # Add a row with the recording's details and its features
    rows.append({

        # The person's id, made of pahaw and the 5 digit person number
        "subject_id": f"pahaw:{rec['subject']:05d}",

        "label": labels[rec["subject"]],
        "source": "pahaw",
        "release": "pahaw",
        "task": TASK_NAME,
        "fs_raw": fs_raw,
        "n_raw": len(t),

        **f,

        # The pressure features from the points where the pen is down
        **pressure_features(t, rec["pressure"][rec["pen_down"]]),

        # The in air features from the whole recording, pen lifts included
        **in_air_features(rec["t"], rec["pen_down"]),
    })

# Save the table
df = pd.DataFrame(rows)
df.to_csv(out, index=False)

# Print what was skipped, the row counts, and the raw points per second
for name, why in skipped:
    print(f"  SKIPPED {name}: {why}")
print(f"{len(df)} rows -> {out}")
print(df.groupby("label").size().rename({0: "healthy", 1: "patient"}))
print(f"fs_raw: median {df.fs_raw.median():.1f} Hz, range {df.fs_raw.min():.1f}-{df.fs_raw.max():.1f}")
