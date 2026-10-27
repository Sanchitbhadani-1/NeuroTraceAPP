# PEN.PY MAKES THE IDEAL SPIRAL SHAPE

import numpy as np


# Make the x and y points of an ideal spiral with the given number of points and turns
def reference_spiral(n_points=10000, turns=4):

    # Make n_points evenly spaced steps from 0 to 1
    progress = np.linspace(0, 1, n_points)

    # Turn each step into an angle, and grow the distance from the center at the same rate
    theta = progress * turns * 2 * np.pi
    r = progress

    # Turn each angle and distance into x and y
    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return x, y
