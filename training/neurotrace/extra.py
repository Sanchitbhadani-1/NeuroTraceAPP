import numpy as np


# Pressure and in-air. NOT in featureOrder, NOT ported to JavaScript, NOT in
# the parity test - they live here so the frozen contract in features.py stays
# untouched while we find out whether they earn a place.

_NAN_PRESSURE = {"pressure_mean": np.nan, "pressure_cv": np.nan, "pressure_trend": np.nan}
_NAN_INAIR = {"inair_time_frac": np.nan, "inair_n_lifts": np.nan,
              "inair_mean_lift_s": np.nan, "inair_max_lift_s": np.nan}


# How hard, how steadily, and whether it fades
def pressure_features(t, p):

    t = np.asarray(t, dtype=float)
    p = np.asarray(p, dtype=float)

    keep = p > 0
    t, p = t[keep], p[keep]
    # In-air samples read 0 on both tablets and would drag the mean down

    if len(p) < 10 or t[-1] <= t[0]:
        return dict(_NAN_PRESSURE)

    mean = float(np.mean(p))

    slope = np.polyfit(t - t[0], p, 1)[0]
    # Straight line through pressure against time - units per second

    return {
        "pressure_mean": mean,
        # Device units. Compare within a dataset only, it cannot transfer

        "pressure_cv": float(np.std(p) / mean),
        # Steadiness of grip as a fraction of the mean, so it DOES transfer

        "pressure_trend": float(slope * (t[-1] - t[0]) / mean),
        # Fraction of mean pressure gained (+) or lost (-) start to end
    }


# How often the pen leaves the surface, and for how long
def in_air_features(t, pen_down):

    t = np.asarray(t, dtype=float)
    up = ~np.asarray(pen_down, dtype=bool)
    # Flip it - we are counting the lifts, not the strokes

    if len(t) < 2 or t[-1] <= t[0]:
        return dict(_NAN_INAIR)

    padded = np.concatenate([[0], up.astype(int), [0]])
    edges = np.diff(padded)
    # Padding with zeros means a lift touching either end still gets both edges

    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)
    # +1 is where a lift begins, -1 is where it ends

    lifts = t[np.minimum(ends, len(t) - 1)] - t[starts]
    total = t[-1] - t[0]

    return {
        "inair_time_frac": float(lifts.sum() / total),
        "inair_n_lifts": int(len(lifts)),
        "inair_mean_lift_s": float(lifts.mean()) if len(lifts) else 0.0,
        "inair_max_lift_s": float(lifts.max()) if len(lifts) else 0.0,
    }
