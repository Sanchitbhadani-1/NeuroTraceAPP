# MAKE_FAKE_COLLECTED.PY MAKES FAKE COLLECTED SESSIONS AND SAVES THEM AS ONE JSON FILE
# RUN IT WITH PYTHONPATH=. python scripts/make_fake_collected.py <out_dir> [--n-healthy 50] [--n-pd 4]

import argparse
import json
from pathlib import Path

import numpy as np

from neurotrace.synth import create_spiral_synth, degrade, FIDELITY_TIERS


# Make one fake session of 3 spiral trials for one person
def session(rng, subject, age, diagnosis, session_no=1):

    # Make the drawing slower and shakier for each year over 55
    age_factor = 1 + 0.02 * max(0, age - 55)

    pd_ = diagnosis == "parkinsons"

    trials = []
    for k in range(3):

        # Make a fake spiral, with a slower and larger shake for Parkinson's
        t, x, y = create_spiral_synth(
            duration=float(rng.normal(14 * age_factor, 2)),
            tremor_hz=float(rng.uniform(4.5, 5.5)) if pd_ else float(rng.uniform(7, 10)),
            tremor_amp=float(rng.normal(35 if pd_ else 6, 3)) * age_factor,
        )

        # Make the spiral look like it was drawn on a tablet
        t, x, y = degrade(t, x, y, **FIDELITY_TIERS["tablet"], seed=int(rng.integers(1e6)))

        # Make random pressures around 0.5, spread wider for Parkinson's
        p = np.clip(rng.normal(0.5, 0.12 if pd_ else 0.06, len(t)), 0, 1)

        # Add the trial with all its points
        trials.append({"trial": k + 1, "task": "spiral",
                       "samples": [{"t": float(a), "x": float(b), "y": float(c), "pressure": float(d)}
                                   for a, b, c, d in zip(t, x, y, p)]})

    # Return the session in the same shape as a real export
    return {"formatVersion": 1, "subjectId": subject, "session": session_no,
            "deviceLabel": "FAKE", "inputType": "pencil", "hand": "right",
            "age": int(age), "diagnosis": diagnosis, "consent": True, "trials": trials}


# Read the output folder, the number of healthy and Parkinson's people, and the seed
ap = argparse.ArgumentParser()
ap.add_argument("out_dir")
ap.add_argument("--n-healthy", type=int, default=50)
ap.add_argument("--n-pd", type=int, default=4)
ap.add_argument("--seed", type=int, default=0)
a = ap.parse_args()

# Set up the random numbers and make the output folder
rng = np.random.default_rng(a.seed)
out = Path(a.out_dir); out.mkdir(parents=True, exist_ok=True)

# Make the healthy sessions, then the Parkinson's sessions
batch = []
for i in range(a.n_healthy):
    batch.append(session(rng, f"fake{i:03d}", rng.integers(55, 90), "none"))
for i in range(a.n_pd):
    batch.append(session(rng, f"fakepd{i:02d}", rng.integers(62, 85), "parkinsons"))

# Save all the sessions to one file
(out / "visit_fake.json").write_text(json.dumps(batch))
print(f"{len(batch)} sessions x 3 trials -> {out / 'visit_fake.json'}")
