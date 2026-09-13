from neurotrace.synth import create_spiral_synth, create_writing_synth
import matplotlib.pyplot as plt

def plot_spiral():
    t1, x1, y1 = create_spiral_synth()
    t2, x2, y2 = create_spiral_synth(tremor_hz=5, tremor_amp=8)

    fig, axes = plt.subplots(1, 2, figsize=(10, 5))

    axes[0].plot(x1, y1, linewidth=0.7)
    axes[0].set_title("clean")
    axes[0].axis("equal")

    axes[1].plot(x2, y2, linewidth=0.7)
    axes[1].set_title("5 Hz tremor, amp 8")
    axes[1].axis("equal")

    plt.show()

# plot_spiral()

def plot_writing(traces, suptitle=None):
    n = len(traces)
    fig, axes = plt.subplots(2, n, figsize=(5 * n, 7), squeeze=False)

    for col, (label, t, x, y) in enumerate(traces):
        shape = axes[0][col]
        shape.plot(x, y, linewidth=0.7, color="#1f4e79")
        shape.set_title(label, fontsize=10)
        shape.axis("equal")
        shape.grid(alpha=0.2)

        series = axes[1][col]
        series.plot(t, y, linewidth=0.7, color="#1f4e79")
        series.set_xlabel("time (s)")
        series.set_ylabel("y")
        series.grid(alpha=0.2)

    if suptitle:
        fig.suptitle(suptitle)

    fig.tight_layout()
    plt.show()

if __name__ == "__main__":
    plot_writing([
        ("healthy", *create_writing_synth()),
        ("PD   size_trend=-0.05", *create_writing_synth(size_trend=-0.05)),
        ("ET   size_trend=+0.05", *create_writing_synth(size_trend=+0.05)),
    ], suptitle="repetitive writing task")