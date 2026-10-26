# PREPROCESS.PY CLEANS UP A RAW DRAWING BEFORE ANY MEASUREMENTS ARE TAKEN
# THE STEPS RUN IN THE SAME ORDER AS CLEANUP IN NT-FEATURES.JS

import numpy as np
from scipy.signal import butter, filtfilt


# Center the drawing on the origin and scale it to an average distance of 1
def normalize(x, y):

    # Center every x and y value on the origin
    x = x - np.mean(x)
    y = y - np.mean(y)

    # Find the average distance of each point from the origin and divide by it
    scale = np.sqrt(np.mean(x**2 + y**2))
    return x / scale, y / scale


# Put the drawing on an even grid of 100 points per second
def resample_uniform(t, x, y, fs=100.0):

    # Turn the times and positions into number arrays
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    # Stop if any point goes backward in time
    if np.any(np.diff(t) <= 0):
        raise ValueError("timestamps must be strictly increasing")

    # Make new evenly spaced times from the first point to the last
    t_grid = np.arange(t[0], t[-1], 1.0 / fs)

    # Fill in the x and y values at each new time
    x_grid = np.interp(t_grid, t, x)
    y_grid = np.interp(t_grid, t, y)

    return t_grid, x_grid, y_grid


# Remove bad points from the drawing
def clean(t, x, y):

    # Turn the times and positions into number arrays
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    # Keep only the points where the time and position are real numbers, not missing or infinite
    finite = np.isfinite(t) & np.isfinite(x) & np.isfinite(y)
    t = t[finite]
    x = x[finite]
    y = y[finite]

    # If no points are left, return the empty drawing
    if len(t) == 0:
        return t, x, y

    # Track the latest time seen so far at each point
    running_max = np.maximum.accumulate(t)

    # Keep the first point, then keep a point only if its time is later than every time before it
    keep = np.empty(len(t), dtype=bool)
    keep[0] = True
    keep[1:] = t[1:] > running_max[:-1]

    return t[keep], x[keep], y[keep]


# Cut off the still parts at the start and end of the drawing
def trim_stationary(t, x, y, threshold=0.05, window=10):

    # If the drawing is too short to check, return it as is
    if len(t) <= window + 1:
        return t, x, y

    # Find how far the pen moves and how much time passes across every 10 points
    dx = x[window:] - x[:-window]
    dy = y[window:] - y[:-window]
    dt = t[window:] - t[:-window]

    # Find the pen's speed across every 10 points
    speed = np.hypot(dx, dy) / dt

    # Mark the places where the pen moves faster than 5% of its median speed
    moving = speed > threshold * np.median(speed)

    # If the pen never moves, return the drawing as is
    if not np.any(moving):
        return t, x, y

    # Find the first and last places where the pen moves
    idx = np.flatnonzero(moving)
    first = idx[0]
    last = idx[-1] + window

    # Keep everything between them, including any pauses in the middle
    return t[first:last + 1], x[first:last + 1], y[first:last + 1]


# Smooth out the drawing by removing anything faster than 15 times per second
def low_pass(t, x, y, fs=100.0, cutoff=15.0, order=4):

    # Build the smoothing filter
    b, a = butter(order, cutoff, btype="low", fs=fs)

    # Stop if the drawing is too short to filter
    if len(x) <= 3 * max(len(a), len(b)):
        raise ValueError(f"trace too short to filter ({len(x)} samples)")

    # Run the filter forward and then backward on x and y
    return t, filtfilt(b, a, x), filtfilt(b, a, y)


# Run every cleanup step in order, the JavaScript runs the same steps in the same order
def preprocess_trace(t, x, y, fs=100.0, cutoff=15.0, trim=True):

    # Remove bad points
    t, x, y = clean(t, x, y)

    # Cut off the still parts at the start and end
    if trim:
        t, x, y = trim_stationary(t, x, y)

    # Put the drawing on an even 100 points per second
    t, x, y = resample_uniform(t, x, y, fs=fs)

    # Center and scale the drawing
    x, y = normalize(x, y)

    # Smooth out the drawing
    t, x, y = low_pass(t, x, y, fs=fs, cutoff=cutoff)

    return t, x, y
