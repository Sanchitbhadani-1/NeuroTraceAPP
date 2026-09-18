"""Builds the parity fixture: raw traces plus the features Python gets from them.

    python parity/make_reference.py [uci_root] [out.json]

Node then runs the same raw traces through app/nt-features.js and compares.
Twenty synthetic traces across all three fidelity tiers, plus ten real UCI
recordings so the test sees genuinely uneven timestamps and integer grids.
"""

import json
import sys
import warnings

import numpy as np

from neurotrace.synth import create_spiral_synth, degrade, FIDELITY_TIERS
from neurotrace.preprocess import preprocess_trace
from neurotrace.features import extract_spiral_features

FS = 100.0


def as_trace(name, t, x, y):
    return {"name": name, "task": "spiral",
            "samples": [{"t": float(a), "x": float(b), "y": float(c)}
                        for a, b, c in zip(t, x, y)]}


def synthetic_cases():
    cases = []
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
    for tier in FIDELITY_TIERS:
        grid.append((f"tier_{tier}_clean", dict(tremor_amp=0.0), tier))
        grid.append((f"tier_{tier}_tremor", dict(tremor_hz=5.5, tremor_amp=20), tier))
        grid.append((f"tier_{tier}_big", dict(tremor_hz=5.0, tremor_amp=60), tier))
        grid.append((f"tier_{tier}_slow", dict(duration=30, tremor_hz=4.5, tremor_amp=12), tier))

    for i, (name, kw, tier) in enumerate(grid):
        t, x, y = create_spiral_synth(**kw)
        if tier:
            t, x, y = degrade(t, x, y, **FIDELITY_TIERS[tier], seed=i)
        cases.append(as_trace(name, t, x, y))
    return cases


def uci_cases(root, n=10):
    from neurotrace.datasets import iter_uci
    out = []
    for rec in iter_uci(root):
        out.append(as_trace(f"uci_{rec['subject_id'].replace(':', '_')}",
                            rec["t"], rec["x"], rec["y"]))
        if len(out) >= n:
            break
    return out


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else None
    out = sys.argv[2] if len(sys.argv) > 2 else "parity/reference.json"

    cases = synthetic_cases()
    if root:
        cases += uci_cases(root)

    kept = []
    for c in cases:
        t = np.array([s["t"] for s in c["samples"]])
        x = np.array([s["x"] for s in c["samples"]])
        y = np.array([s["y"] for s in c["samples"]])
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                c["features"] = extract_spiral_features(*preprocess_trace(t, x, y, fs=FS), fs=FS)
        except ValueError as e:
            print(f"  skipped {c['name']}: {e}")
            continue
        kept.append(c)

    json.dump({"fs": FS, "cases": kept}, open(out, "w"))
    print(f"{len(kept)} cases -> {out}")
