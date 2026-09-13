import numpy as np


# The ideal spiral every drawing is measured against - the ruler.
# Kept separate from create_spiral_synth on purpose: that one makes test
# data, this one is a measurement standard and must never change.
def reference_spiral(n_points=10000, turns=4):

    progress = np.linspace(0, 1, n_points)
    # n_points is resolution, not a sample rate - a shape has no time axis

    theta = progress * turns * 2 * np.pi
    r = progress
    # Radius grows straight with the angle, which is what makes it Archimedean

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return x, y
