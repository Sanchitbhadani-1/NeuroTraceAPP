import numpy as np
import matplotlib.pyplot as plt

def create_spiral_synth(duration=20, fs=240, turns=4, radius=300, tremor_hz=0.0, tremor_amp=0.0):
    n_samples = duration * fs
    t = np.linspace(0, duration, int(n_samples))
    progress = t/duration

    theta = progress * turns * 2 * np.pi
    r = (progress * radius) + (tremor_amp * np.sin(2 * np.pi * tremor_hz * t))

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return t, x, y

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

plot_spiral()