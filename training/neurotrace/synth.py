import numpy as np


def create_spiral_synth(duration=20, fs=240, turns=4, radius=300, tremor_hz=0.0, tremor_amp=0.0):
    n_samples = duration * fs
    t = np.linspace(0, duration, int(n_samples))
    progress = t/duration

    theta = progress * turns * 2 * np.pi
    r = (progress * radius) + (tremor_amp * np.sin(2 * np.pi * tremor_hz * t))

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return t, x, y


def create_handwriting_synth(duration=10, fs=100, freq=2.0, base_amplitude=40, shrink_pct=0.0):
    """Repetitive cursive-like writing: x advances steadily, y oscillates at `freq` Hz
    with an amplitude that declines linearly from base_amplitude to
    base_amplitude * (1 - shrink_pct) over the trace. shrink_pct=0.30 -> writing
    shrinks 30% by the end, for validating amplitude-decline extraction."""
    n_samples = int(duration * fs)
    t = np.linspace(0, duration, n_samples)
    envelope = base_amplitude * (1 - shrink_pct * (t / duration))
    x = t * 50
    y = envelope * np.sin(2 * np.pi * freq * t)
    return t, x, y


def plot_spiral():
    import matplotlib.pyplot as plt

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


if __name__ == "__main__":
    plot_spiral()
