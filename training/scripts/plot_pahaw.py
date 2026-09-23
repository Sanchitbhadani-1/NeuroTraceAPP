"""Plot one PaHaW subject's spiral and first writing task, side by side.

    PYTHONPATH=. python scripts/plot_pahaw.py <pahaw_root> <subject_number>
"""

import sys
from pathlib import Path

import matplotlib.pyplot as plt

from neurotrace.pahaw import load_svc, on_surface

root = Path(sys.argv[1])
subject = int(sys.argv[2])

fig, axes = plt.subplots(1, 2, figsize=(11, 5))

for ax, task_id, title in ((axes[0], 1, "task 1: spiral"), (axes[1], 2, "task 2: l l l l")):

    matches = sorted(root.rglob(f"{subject:05d}__{task_id}_*.svc"))
    # 05d pads 4 into 00004, the * is the attempt number

    if not matches:
        ax.set_title(f"{title} - no file found")
        continue

    rec = load_svc(matches[0])
    t, x, y = on_surface(rec)
    # Pen-down only, or air strokes draw lines across the picture

    ax.plot(x, y, lw=0.8)

    ax.set_aspect("equal")
    # Without this a circle looks like an oval and you cannot trust the shape

    ax.set_title(f"{title}\n{matches[0].name}  n={len(x)}  {t[-1]:.1f}s  fs~{len(t) / t[-1]:.0f} Hz")
    # fs is CRUDE - on_surface dropped samples but the clock kept running, so
    # it under-reads. Good enough to catch a units disaster, not to quote

plt.tight_layout()
plt.show()

# THE CHECK IS THE WRITING, NOT THE SPIRAL. Mirror a spiral and you get a
# spiral. A row of l's is wide and short - tall and narrow means x and y are
# swapped in pahaw.COLUMNS and every distance feature would be silently wrong.
