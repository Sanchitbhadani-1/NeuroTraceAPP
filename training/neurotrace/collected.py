import json
from pathlib import Path

import numpy as np


# Traces WE collect, on OUR device. datasets.py and pahaw.py are somebody
# else's tablet; these are what the runtime reference is built from.
# Format is in docs/COLLECTED_FORMAT.md.

BRACKETS = ("50s", "60s", "70s", "80+")
# A healthy 80 year old draws differently from a healthy 55 year old, so the
# reference is split by these and the app picks the user's

HEALTHY = "none"
# Only this diagnosis goes in the healthy reference


def age_bracket(age):
    if age is None:
        return None
    if age < 60:
        return "50s"
    if age < 70:
        return "60s"
    if age < 80:
        return "70s"
    return "80+"


# One exported session - one person, one sitting - into one record per trial
def parse_session(obj):

    subject = obj["subjectId"]
    diagnosis = obj.get("diagnosis", HEALTHY)

    bracket = obj.get("ageBracket") or age_bracket(obj.get("age"))
    # Take the bracket if the app sent one, otherwise work it out from the age

    for trial in obj["trials"]:
        samples = trial["samples"]
        t = np.array([s["t"] for s in samples], dtype=float)
        x = np.array([s["x"] for s in samples], dtype=float)
        y = np.array([s["y"] for s in samples], dtype=float)
        p = np.array([s.get("pressure", 0.0) for s in samples], dtype=float)
        # .get so a finger trace with no pressure reads 0 instead of crashing

        yield {
            "t": t, "x": x, "y": y, "pressure": p,
            "subject_id": f"nt:{subject}",

            "label": int(diagnosis == "parkinsons"),
            "diagnosis": diagnosis,
            # TWO fields on purpose - essential tremor is label 0 but is NOT
            # healthy. The reference filters on diagnosis, never on label

            "source": "neurotrace",
            "release": "collected",
            "task": trial.get("task", obj.get("task", "spiral")),
            "session": int(obj.get("session", 1)),
            "trial": int(trial.get("trial", 1)),
            "age_bracket": bracket,
            "hand": obj.get("hand"),
            "device": obj.get("deviceLabel"),
            "input_type": trial.get("inputType", obj.get("inputType")),
            "fs": estimate_fs(t),
        }


def estimate_fs(t):
    dt = np.diff(t)
    dt = dt[dt > 0]
    # Median not mean - a pen lift would drag the mean down
    return float(1.0 / np.median(dt)) if len(dt) else float("nan")


# Every trial in every export file under root
def iter_collected(root, task="spiral"):

    root = Path(root)
    paths = [root] if root.is_file() else sorted(root.rglob("*.json"))

    for path in paths:
        blob = json.loads(path.read_text())

        sessions = blob if isinstance(blob, list) else [blob]
        # One file may hold one session or a whole visit's worth

        for obj in sessions:
            for rec in parse_session(obj):
                if rec["task"] == task:
                    yield rec
