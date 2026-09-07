import numpy as np

from .preprocess import normalize

# Ideal spiral that is being recorded against. Kept for features.distance_to_reference;
# spiral_deviation below fits its own rate instead and needs no fixed reference.
def reference_spiral(n_points=10000, turns=4):
    progress = np.linspace(0, 1, n_points)
    theta = progress * turns * 2 * np.pi
    r = progress

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return x, y


def spiral_deviation(x, y):
    """Mean |actual radius - best-fit ideal radius| at each sample's own
    angle, in the unit-RMS-radius frame. An archimedean spiral has r = k *
    theta for some rate k; we least-squares fit k from the data itself
    (through the origin) rather than assume a fixed turn count, so this is
    invariant to rotation (theta zeroed at the first sample), turn count
    (drawing 3.5 or 4.5 turns of a steady spiral still fits its own k well),
    and overall size (that's what normalize() buys us). Only wobble around
    whatever steady spiral the strokes describe moves the number.
    """
    nx, ny = normalize(x, y)
    theta = np.unwrap(np.arctan2(ny, nx))
    theta = np.abs(theta - theta[0])
    r = np.hypot(nx, ny)

    k = np.sum(r * theta) / np.sum(theta**2)
    ideal_r = k * theta
    return float(np.mean(np.abs(r - ideal_r)))
