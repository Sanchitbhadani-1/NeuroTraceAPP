"""Turns published datasets into the same (t, x, y) shape the app produces."""

from pathlib import Path

import numpy as np


# --- UCI 395 ---------------------------------------------------------
# "Parkinson Disease Spiral Drawings Using Digitized Graphics Tablet".
# Semicolon CSV, no header, one row per sample:
#   X ; Y ; Z ; Pressure ; GripAngle ; Timestamp ; Test ID
# Timestamp is MILLISECONDS off an arbitrary clock, so only gaps matter.
# Z is 0 in most files and 0/12/24 in a few - unusable, ignored.
UCI_COLUMNS = ("x", "y", "z", "pressure", "grip", "t_ms", "test_id")

# Test IDs, verbatim from the readme
UCI_TESTS = {
    0: "static_spiral",    # draw on the given spiral pattern
    1: "dynamic_spiral",   # the pattern blinks, subject keeps drawing
    2: "circle",           # circles around a red point
}

# Only test 0 matches what our app asks for. 1 and 2 are different tasks
# and must never be mixed in as extra spirals.
UCI_DEFAULT_TEST = 0


def parse_uci(path):
    rows = np.loadtxt(path, delimiter=";")
    return {name: rows[:, i] for i, name in enumerate(UCI_COLUMNS)}


def load_uci(path, test_id=UCI_DEFAULT_TEST):
    path = Path(path)
    rec = parse_uci(path)

    keep = rec["test_id"] == test_id
    if not np.any(keep):
        return None
    # Some subjects are missing a test entirely - caller skips these

    t_ms = rec["t_ms"][keep]
    t = (t_ms - t_ms[0]) / 1000.0
    # Seconds from the first sample of THIS test, not the file

    group = path.parent.name          # "control" or "parkinson" - authoritative
    release = path.parent.parent.name  # "hw_dataset" or "new_dataset"

    return {
        "t": t,
        "x": rec["x"][keep],
        "y": rec["y"][keep],
        "pressure": rec["pressure"][keep],
        "grip": rec["grip"][keep],
        "subject_id": f"uci:{release}:{path.stem}",
        # Prefixed, because the two releases number their subjects separately
        "label": int(group == "parkinson"),
        "source": "uci395",
        "task": "spiral",
        "test": UCI_TESTS[test_id],
        "fs": estimate_fs(t),
    }


def iter_uci(root, test_id=UCI_DEFAULT_TEST):
    root = Path(root)
    for path in sorted(root.rglob("*.txt")):
        if path.name.lower().startswith("readme"):
            continue
        rec = load_uci(path, test_id=test_id)
        if rec is not None:
            yield rec


# --- shared ----------------------------------------------------------

def estimate_fs(t):
    # Median, not mean - one long pause would drag the mean down. Files come
    # in at 111 Hz or 143 Hz, so NEVER hardcode this.
    dt = np.diff(t)
    dt = dt[dt > 0]
    if len(dt) == 0:
        return float("nan")
    return float(1.0 / np.median(dt))


# NewHandPD is NOT here on purpose. Its signal files are six smart-pen
# voltage channels (microphone, grip, refill pressure, tilt X/Y/Z), not pen
# coordinates, so there is no (x, y) to feed the pipeline. See
# docs/DATASETS.md.
