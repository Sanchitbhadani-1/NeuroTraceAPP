# PLOT_PAHAW.PY DRAWS ONE PAHAW PERSON'S SPIRAL AND FIRST WRITING TASK SIDE BY SIDE
# RUN IT WITH PYTHONPATH=. python scripts/plot_pahaw.py <pahaw_root> <subject_number>

import sys
from pathlib import Path

import matplotlib.pyplot as plt

from neurotrace.pahaw import load_svc, on_surface


# Read the data folder and the person's number
root = Path(sys.argv[1])
subject = int(sys.argv[2])

# Make a picture with two plots side by side
fig, axes = plt.subplots(1, 2, figsize=(11, 5))

# Fill the left plot with task 1 and the right plot with task 2
for ax, task_id, title in ((axes[0], 1, "task 1: spiral"), (axes[1], 2, "task 2: l l l l")):

    # Find the files for this person and task, with the number padded to 5 digits
    matches = sorted(root.rglob(f"{subject:05d}__{task_id}_*.svc"))

    # If there is no file, say so in the title and move on
    if not matches:
        ax.set_title(f"{title} - no file found")
        continue

    # Load the first file and keep only the points where the pen touches the tablet
    rec = load_svc(matches[0])
    t, x, y = on_surface(rec)

    ax.plot(x, y, lw=0.8)

    # Use the same scale on both axes
    ax.set_aspect("equal")

    # Show the file name, number of points, length in seconds, and points per second in the title
    ax.set_title(f"{title}\n{matches[0].name}  n={len(x)}  {t[-1]:.1f}s  fs~{len(t) / t[-1]:.0f} Hz")

# Fit the plots together and show the picture
plt.tight_layout()
plt.show()
