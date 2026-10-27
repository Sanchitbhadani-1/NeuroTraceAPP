# PAHAW.PY READS THE .SVC DRAWING FILES FROM THE PAHAW DATASET

import re
from pathlib import Path

import numpy as np


# The names of the 7 columns in each .svc row, in order, with y first
COLUMNS = ("y", "x", "t_ms", "pen", "azimuth", "altitude", "pressure")

# The name of each task number used in the file names
TASKS = {
    1: "spiral",
    2: "l",
    3: "le",
    4: "les",
    5: "lektorka",
    6: "porovnat",
    7: "nepopadnout",
    8: "sentence",
}

# Matches file names like "00026__1_1.svc" and pulls out the subject and task numbers
_NAME = re.compile(r"^(?P<subject>\d+)__(?P<task>\d+)_\d+\.svc$")


# Turn the text of one .svc file into named arrays
def parse_svc(text):

    # Drop empty lines and read the number of samples from the first line
    lines = [ln for ln in text.strip().splitlines() if ln.strip()]
    n = int(lines[0].split()[0])

    # Read that many rows of numbers after the first line
    rows = np.array([[float(v) for v in ln.split()] for ln in lines[1:1 + n]])

    # Stop if the rows do not have 7 columns
    if rows.shape[1] != len(COLUMNS):
        raise ValueError(f"expected {len(COLUMNS)} columns, got {rows.shape[1]}")

    # Make one named array per column
    rec = {name: rows[:, i] for i, name in enumerate(COLUMNS)}

    # Turn the times into seconds from the first sample
    t_ms = rec.pop("t_ms")
    rec["t"] = (t_ms - t_ms[0]) / 1000.0

    # Turn the pen column into True where the pen is down
    rec["pen_down"] = rec.pop("pen") > 0

    return rec


# Read one .svc file and add the subject and task from its file name
def load_svc(path):

    # Read and turn the file into arrays
    path = Path(path)
    rec = parse_svc(path.read_text())

    # Add the subject number, task number and task name, or None if the file name does not match
    m = _NAME.match(path.name)
    rec["subject"] = int(m["subject"]) if m else None
    rec["task_id"] = int(m["task"]) if m else None
    rec["task"] = TASKS.get(rec["task_id"])
    return rec


# Keep only the times and positions where the pen is down
def on_surface(rec):

    keep = rec["pen_down"]
    return rec["t"][keep], rec["x"][keep], rec["y"][keep]


# Give back every .svc file under root, or only the ones for task_id if it is given
def iter_svc(root, task_id=None):

    root = Path(root)
    for path in sorted(root.rglob("*.svc")):

        # Skip files whose names do not match
        m = _NAME.match(path.name)
        if not m:
            continue

        # Skip files for other tasks
        if task_id is not None and (not m or int(m["task"]) != task_id):
            continue
        yield path
