# DATASETS.PY TURNS PUBLISHED DRAWING DATASETS INTO THE SAME TIME, X AND Y LISTS THE APP MAKES

from pathlib import Path

import numpy as np


# UCI 395

# The names of the 7 columns in each UCI row, in order
UCI_COLUMNS = ("x", "y", "z", "pressure", "grip", "t_ms", "test_id")

# The name of each UCI test number
UCI_TESTS = {
    0: "static_spiral",
    1: "dynamic_spiral",
    2: "circle",
}

# The UCI test number to load when none is given
UCI_DEFAULT_TEST = 0


# Read a UCI file and give back each column by name
def parse_uci(path):
    rows = np.loadtxt(path, delimiter=";")
    return {name: rows[:, i] for i, name in enumerate(UCI_COLUMNS)}


# Load one test from one UCI file as a record, or None if the file has no rows for that test
def load_uci(path, test_id=UCI_DEFAULT_TEST):
    path = Path(path)
    rec = parse_uci(path)

    # Keep only the rows for this test, or give back None if there are none
    keep = rec["test_id"] == test_id
    if not np.any(keep):
        return None

    # Turn the times into seconds from the first row of this test
    t_ms = rec["t_ms"][keep]
    t = (t_ms - t_ms[0]) / 1000.0

    # Read the group from the folder name, and the release from the folder above it
    group = path.parent.name
    release = path.parent.parent.name

    return {
        "t": t,
        "x": rec["x"][keep],
        "y": rec["y"][keep],
        "pressure": rec["pressure"][keep],
        "grip": rec["grip"][keep],

        # Build the subject id from the release name and the file name
        "subject_id": f"uci:{release}:{path.stem}",

        # Set label to 1 when the file is in the parkinson folder
        "label": int(group == "parkinson"),
        "source": "uci395",
        "task": "spiral",
        "test": UCI_TESTS[test_id],
        "fs": estimate_fs(t),
    }


# Give back a record for every UCI file under root that has the given test
def iter_uci(root, test_id=UCI_DEFAULT_TEST):
    root = Path(root)
    for path in sorted(root.rglob("*.txt")):

        # Skip readme files
        if path.name.lower().startswith("readme"):
            continue

        # Skip files that have no rows for this test
        rec = load_uci(path, test_id=test_id)
        if rec is not None:
            yield rec


# SHARED

# Work out the samples per second from the times
def estimate_fs(t):

    # Find the gaps between times, keeping only gaps above 0
    dt = np.diff(t)
    dt = dt[dt > 0]

    # Give back NaN if there are no gaps
    if len(dt) == 0:
        return float("nan")

    # Divide 1 by the middle gap
    return float(1.0 / np.median(dt))
