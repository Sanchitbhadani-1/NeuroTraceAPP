import numpy as np


# Ideal spiral that is being recorded against
def reference_spiral(n_points=10000, turns=4):
    progress = np.linspace(0, 1, n_points)
    theta = progress * turns * 2 * np.pi
    r = progress

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return x, y