import numpy as np
from scipy.spatial import cKDTree


def distance_to_reference(x, y, rx, ry):
    tree = cKDTree(np.column_stack([rx, ry]))
    d, idx = tree.query(np.column_stack([x, y]))

    sample_r = np.hypot(x, y)
    nearest_r = np.hypot(rx[idx], ry[idx])

    return np.where(sample_r >= nearest_r, d, -d)