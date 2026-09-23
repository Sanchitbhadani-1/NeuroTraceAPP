import re
from pathlib import Path

import numpy as np


# VERIFY against the readme in data/PaHaW before trusting any feature.
# If the order is wrong every spiral is mirrored and every distance feature
# is silently wrong. Note y comes FIRST. Plot one file and look at it.
COLUMNS = ("y", "x", "t_ms", "pen", "azimuth", "altitude", "pressure")

# VERIFY too - task numbers as used in the filenames
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

_NAME = re.compile(r"^(?P<subject>\d+)__(?P<task>\d+)_\d+\.svc$")
# Matches "00026__1_1.svc" and pulls out the subject and task numbers


# Turns the text of one .svc file into arrays
def parse_svc(text):

    lines = [ln for ln in text.strip().splitlines() if ln.strip()]
    n = int(lines[0].split()[0])
    # First line is how many samples follow

    rows = np.array([[float(v) for v in ln.split()] for ln in lines[1:1 + n]])

    if rows.shape[1] != len(COLUMNS):
        raise ValueError(f"expected {len(COLUMNS)} columns, got {rows.shape[1]}")

    rec = {name: rows[:, i] for i, name in enumerate(COLUMNS)}
    # One array per column, named

    t_ms = rec.pop("t_ms")
    rec["t"] = (t_ms - t_ms[0]) / 1000.0
    # Milliseconds to seconds, rebased so the trace starts at 0

    rec["pen_down"] = rec.pop("pen") > 0
    # Pen status into a True/False array

    return rec


# Same thing but from a file, plus the subject and task from the filename
def load_svc(path):

    path = Path(path)
    rec = parse_svc(path.read_text())

    m = _NAME.match(path.name)
    rec["subject"] = int(m["subject"]) if m else None
    rec["task_id"] = int(m["task"]) if m else None
    rec["task"] = TASKS.get(rec["task_id"])
    return rec


# Drops the samples where the pen was in the air
def on_surface(rec):
    # Our app only records pen-down, so the training data has to match or
    # the features come out different

    keep = rec["pen_down"]
    return rec["t"][keep], rec["x"][keep], rec["y"][keep]


# Walks a folder and hands back every .svc file, optionally one task only
def iter_svc(root, task_id=None):

    root = Path(root)
    for path in sorted(root.rglob("*.svc")):
        m = _NAME.match(path.name)
        if not m:
            continue
        if task_id is not None and (not m or int(m["task"]) != task_id):
            continue
        yield path
