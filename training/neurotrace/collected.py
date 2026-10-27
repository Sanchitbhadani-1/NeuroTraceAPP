# COLLECTED.PY READS THE DRAWINGS THE NEUROTRACE APP EXPORTS
# IT TURNS EACH EXPORTED SESSION INTO ONE RECORD PER TRIAL

import json
from pathlib import Path

import numpy as np


# The age groups the reference is split into
BRACKETS = ("50s", "60s", "70s", "80+")


# The diagnosis that counts as healthy
HEALTHY = "none"


# Turn an age into its age group, or None if there is no age
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


# Turn one exported session into one record per trial
def parse_session(obj):

    # Read who drew it and their diagnosis, using healthy if none is given
    subject = obj["subjectId"]
    diagnosis = obj.get("diagnosis", HEALTHY)

    # Use the age group the app sent, or work it out from the age
    bracket = obj.get("ageBracket") or age_bracket(obj.get("age"))

    for trial in obj["trials"]:

        # Pull the times, positions and pressure out of each sample
        samples = trial["samples"]
        t = np.array([s["t"] for s in samples], dtype=float)
        x = np.array([s["x"] for s in samples], dtype=float)
        y = np.array([s["y"] for s in samples], dtype=float)

        # Use 0 for the pressure when a sample has none
        p = np.array([s.get("pressure", 0.0) for s in samples], dtype=float)

        # Give back the trial as one record
        yield {
            "t": t, "x": x, "y": y, "pressure": p,
            "subject_id": f"nt:{subject}",

            # Set label to 1 only for Parkinson's, and keep the full diagnosis too
            "label": int(diagnosis == "parkinsons"),
            "diagnosis": diagnosis,

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


# Work out the samples per second from the times
def estimate_fs(t):

    # Find the gaps between times, keeping only gaps above 0
    dt = np.diff(t)
    dt = dt[dt > 0]

    # Divide 1 by the middle gap, or give back NaN if there are no gaps
    return float(1.0 / np.median(dt)) if len(dt) else float("nan")


# Give back every trial of the given task in every export file under root
def iter_collected(root, task="spiral"):

    # Use root itself if it is a file, or every JSON file under it
    root = Path(root)
    paths = [root] if root.is_file() else sorted(root.rglob("*.json"))

    for path in paths:
        blob = json.loads(path.read_text())

        # Treat the file as a list of sessions, even if it holds just one
        sessions = blob if isinstance(blob, list) else [blob]

        # Keep only the trials of the given task
        for obj in sessions:
            for rec in parse_session(obj):
                if rec["task"] == task:
                    yield rec
