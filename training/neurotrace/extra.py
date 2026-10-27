# EXTRA.PY MEASURES PEN PRESSURE AND PEN LIFTS IN A DRAWING
# THESE NUMBERS ARE KEPT APART FROM THE 12 NUMBERS IN FEATURES.PY

import numpy as np


# The pressure numbers to give back when there is too little to measure
_NAN_PRESSURE = {"pressure_mean": np.nan, "pressure_cv": np.nan, "pressure_trend": np.nan}

# The pen lift numbers to give back when there is too little to measure
_NAN_INAIR = {"inair_time_frac": np.nan, "inair_n_lifts": np.nan,
              "inair_mean_lift_s": np.nan, "inair_max_lift_s": np.nan}


# Measure how hard the pen presses, how steady it is, and how it changes over the drawing
def pressure_features(t, p):

    # Turn the times and pressures into number arrays
    t = np.asarray(t, dtype=float)
    p = np.asarray(p, dtype=float)

    # Keep only the points where the pressure is above 0
    keep = p > 0
    t, p = t[keep], p[keep]

    # Give back NaN for everything if there are fewer than 10 points or no time passes
    if len(p) < 10 or t[-1] <= t[0]:
        return dict(_NAN_PRESSURE)

    # Find the average pressure
    mean = float(np.mean(p))

    # Fit a straight line to pressure against time and take its slope
    slope = np.polyfit(t - t[0], p, 1)[0]

    return {

        # The average pressure in the device's own units
        "pressure_mean": mean,

        # How much the pressure varies, as a share of the average
        "pressure_cv": float(np.std(p) / mean),

        # How much the pressure goes up or down from start to end, as a share of the average
        "pressure_trend": float(slope * (t[-1] - t[0]) / mean),
    }


# Measure how often the pen leaves the surface, and for how long
def in_air_features(t, pen_down):

    # Turn the times into a number array and flip pen down into pen up
    t = np.asarray(t, dtype=float)
    up = ~np.asarray(pen_down, dtype=bool)

    # Give back NaN for everything if there are fewer than 2 points or no time passes
    if len(t) < 2 or t[-1] <= t[0]:
        return dict(_NAN_INAIR)

    # Add a 0 at each end of the pen up marks and find where they change
    padded = np.concatenate([[0], up.astype(int), [0]])
    edges = np.diff(padded)

    # Find where each lift starts and ends
    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)

    # Find how long each lift lasts and how long the whole drawing lasts
    lifts = t[np.minimum(ends, len(t) - 1)] - t[starts]
    total = t[-1] - t[0]

    # Give back the share of time lifted, the number of lifts, and the average and longest lift
    return {
        "inair_time_frac": float(lifts.sum() / total),
        "inair_n_lifts": int(len(lifts)),
        "inair_mean_lift_s": float(lifts.mean()) if len(lifts) else 0.0,
        "inair_max_lift_s": float(lifts.max()) if len(lifts) else 0.0,
    }
