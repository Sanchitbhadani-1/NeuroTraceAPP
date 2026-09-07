import numpy as np
from scipy.spatial import cKDTree


def distance_to_reference(x, y, rx, ry):
    tree = cKDTree(np.column_stack([rx, ry]))
    d, idx = tree.query(np.column_stack([x, y]))

    sample_r = np.hypot(x, y)
    nearest_r = np.hypot(rx[idx], ry[idx])

    return np.where(sample_r >= nearest_r, d, -d)



def change_of_radius_direction(x, y):
    r = np.hypot(x, y)
    dr = np.diff(r)
    dr = dr[dr != 0]

    if len(dr) < 2:
        return 0

    s = np.sign(dr)
    return int(np.count_nonzero(s[:-1] != s[1:]))



def kinematics(t, x, y):
    dt = np.diff(t)

    vx = np.diff(x) / dt
    vy = np.diff(y) / dt
    speed = np.hypot(vx, vy)

    ax = np.diff(vx) / dt[1:]
    ay = np.diff(vy) / dt[1:]
    accel = np.hypot(ax, ay)

    jx = np.diff(ax) / dt[2:]
    jy = np.diff(ay) / dt[2:]
    jerk = np.hypot(jx, jy)

    return speed, accel, jerk