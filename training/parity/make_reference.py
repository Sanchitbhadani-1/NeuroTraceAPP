# MAKE_REFERENCE.PY SAVES TEST DRAWINGS AND THE SPIRAL NUMBERS PYTHON GETS FROM THEM TO ONE JSON FILE
# IT USES 20 MADE UP SPIRALS, PLUS UP TO 10 REAL UCI DRAWINGS WHEN A UCI FOLDER IS GIVEN
# RUN IT FROM training/ WITH python parity/make_reference.py [uci_root] [out.json]

import json
import sys
import warnings

import numpy as np

from neurotrace.synth import create_spiral_synth, degrade, FIDELITY_TIERS
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features

# The samples per second the drawings are cleaned to
FS = 100.0


# Turn a name, times and positions into a spiral drawing in the shape the app makes
def as_trace(name, t, x, y):
    return {"name": name, "task": "spiral",
            "samples": [{"t": float(a), "x": float(b), "y": float(c)}
                        for a, b, c in zip(t, x, y)]}


# Make the 20 made up spiral drawings
def synthetic_cases():
    cases = []

    # List 8 spirals by name and settings, with no device kind
    grid = [
        ("clean",          dict(tremor_amp=0.0),                      None),
        ("tremor_5hz",     dict(tremor_hz=5.0, tremor_amp=8),         None),
        ("tremor_5_5hz",   dict(tremor_hz=5.5, tremor_amp=20),        None),
        ("tremor_9hz_et",  dict(tremor_hz=9.0, tremor_amp=8),         None),
        ("big_reversals",  dict(tremor_hz=5.0, tremor_amp=60),        None),
        ("few_turns",      dict(turns=2.0, tremor_hz=5.0, tremor_amp=8), None),
        ("many_turns",     dict(turns=6.0, tremor_hz=5.0, tremor_amp=8), None),
        ("short",          dict(duration=8, tremor_hz=5.0, tremor_amp=8), None),
    ]

    # Add 4 more spirals for each device kind
    for tier in FIDELITY_TIERS:
        grid.append((f"tier_{tier}_clean", dict(tremor_amp=0.0), tier))
        grid.append((f"tier_{tier}_tremor", dict(tremor_hz=5.5, tremor_amp=20), tier))
        grid.append((f"tier_{tier}_big", dict(tremor_hz=5.0, tremor_amp=60), tier))
        grid.append((f"tier_{tier}_slow", dict(duration=30, tremor_hz=4.5, tremor_amp=12), tier))

    # Make each spiral, make it look like its device kind if it has one, and turn it into a drawing
    for i, (name, kw, tier) in enumerate(grid):
        t, x, y = create_spiral_synth(**kw)
        if tier:
            t, x, y = degrade(t, x, y, **FIDELITY_TIERS[tier], seed=i)
        cases.append(as_trace(name, t, x, y))
    return cases


# Turn the first n UCI spirals under root into drawings
def uci_cases(root, n=10):
    from neurotrace.datasets import iter_uci
    out = []
    for rec in iter_uci(root):

        # Name each drawing after its subject id, with colons turned into underscores
        out.append(as_trace(f"uci_{rec['subject_id'].replace(':', '_')}",
                            rec["t"], rec["x"], rec["y"]))

        # Stop once there are n drawings
        if len(out) >= n:
            break
    return out


# When run, build the drawings, find their numbers and save them
if __name__ == "__main__":

    # Read the UCI folder and the output file from the command line, if given
    root = sys.argv[1] if len(sys.argv) > 1 else None
    out = sys.argv[2] if len(sys.argv) > 2 else "parity/reference.json"

    # Make the made up drawings, and add the UCI drawings if a folder is given
    cases = synthetic_cases()
    if root:
        cases += uci_cases(root)

    kept = []
    for c in cases:

        # Pull the times and positions out of the drawing
        t = np.array([s["t"] for s in c["samples"]])
        x = np.array([s["x"] for s in c["samples"]])
        y = np.array([s["y"] for s in c["samples"]])

        # Clean the drawing and find its spiral numbers with warnings hidden, or skip it if that fails
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                c["features"] = extract_spiral_features(*preprocess_trace(t, x, y, fs=FS), fs=FS)
        except ValueError as e:
            print(f"  skipped {c['name']}: {e}")
            continue
        kept.append(c)

    # Save the kept drawings and their numbers to the output file
    json.dump({"fs": FS, "cases": kept}, open(out, "w"))
    print(f"{len(kept)} cases -> {out}")
