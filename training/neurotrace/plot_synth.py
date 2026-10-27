# PLOT_SYNTH.PY DRAWS MADE UP SPIRALS AND WRITING ON SCREEN
# RUN IT FROM training/ WITH python -m neurotrace.plot_synth

from neurotrace.synth import create_spiral_synth, create_writing_synth
import matplotlib.pyplot as plt


# Show a clean made up spiral next to one with a 5 per second shake
def plot_spiral():

    # Make the two spirals
    t1, x1, y1 = create_spiral_synth()
    t2, x2, y2 = create_spiral_synth(tremor_hz=5, tremor_amp=8)

    fig, axes = plt.subplots(1, 2, figsize=(10, 5))

    # Draw the clean spiral on the left
    axes[0].plot(x1, y1, linewidth=0.7)
    axes[0].set_title("clean")
    axes[0].axis("equal")

    # Draw the shaky spiral on the right
    axes[1].plot(x2, y2, linewidth=0.7)
    axes[1].set_title("5 Hz tremor, amp 8")
    axes[1].axis("equal")

    plt.show()


# Show each writing drawing as its shape on top and its height over time below
def plot_writing(traces, suptitle=None):

    # Make one column of two plots for each drawing
    n = len(traces)
    fig, axes = plt.subplots(2, n, figsize=(5 * n, 7), squeeze=False)

    for col, (label, t, x, y) in enumerate(traces):

        # Draw the shape on the top plot
        shape = axes[0][col]
        shape.plot(x, y, linewidth=0.7, color="#1f4e79")
        shape.set_title(label, fontsize=10)
        shape.axis("equal")
        shape.grid(alpha=0.2)

        # Draw the height over time on the bottom plot
        series = axes[1][col]
        series.plot(t, y, linewidth=0.7, color="#1f4e79")
        series.set_xlabel("time (s)")
        series.set_ylabel("y")
        series.grid(alpha=0.2)

    # Add the overall title if one is given
    if suptitle:
        fig.suptitle(suptitle)

    fig.tight_layout()
    plt.show()


# When run, show a healthy, a shrinking and a growing writing drawing
if __name__ == "__main__":
    plot_writing([
        ("healthy", *create_writing_synth()),
        ("PD   size_trend=-0.05", *create_writing_synth(size_trend=-0.05)),
        ("ET   size_trend=+0.05", *create_writing_synth(size_trend=+0.05)),
    ], suptitle="repetitive writing task")
