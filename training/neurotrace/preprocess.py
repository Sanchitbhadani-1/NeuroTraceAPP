import numpy as np
from scipy.signal import butter, filtfilt


# Center on the origin, then scale to unit RMS radius
def normalize(x, y):
    x = x - np.mean(x)
    y = y - np.mean(y)
    scale = np.sqrt(np.mean(x**2 + y**2))
    return x / scale, y / scale



def resample_uniform(t, x, y, fs=100.0):
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    if np.any(np.diff(t) <= 0):
        raise ValueError("timestamps must be strictly increasing")

    t_grid = np.arange(t[0], t[-1], 1.0 / fs)

    x_grid = np.interp(t_grid, t, x)
    y_grid = np.interp(t_grid, t, y)

    return t_grid, x_grid, y_grid



def clean(t, x, y):
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    finite = ~(np.isnan(t) | np.isnan(x) | np.isnan(y))
    t, x, y = t[finite], x[finite], y[finite]

    if len(t) == 0:
        return t, x, y

    running_max = np.maximum.accumulate(t)
    keep = np.empty(len(t), dtype=bool)
    keep[0] = True
    keep[1:] = t[1:] > running_max[:-1]

    return t[keep], x[keep], y[keep]



def trim_stationary(t, x, y, threshold=0.05):
    speed = np.hypot(np.diff(x), np.diff(y)) / np.diff(t)
    moving = speed > threshold * np.median(speed)

    if not np.any(moving):
        return t, x, y

    first = np.argmax(moving)
    last = len(moving) - np.argmax(moving[::-1])

    return t[first:last + 1], x[first:last + 1], y[first:last + 1]



def low_pass(t, x, y, fs=100.0, cutoff=15.0, order=4):
    b, a = butter(order, cutoff, btype="low", fs=fs)
    return t, filtfilt(b, a, x), filtfilt(b, a, y)



def preprocess_trace(t, x, y, fs=100.0, cutoff=15.0, trim=True):
    t, x, y = clean(t, x, y)
    if trim:
        t, x, y = trim_stationary(t, x, y)
    t, x, y = resample_uniform(t, x, y, fs=fs)
    x, y = normalize(x, y)
    t, x, y = low_pass(t, x, y, fs=fs, cutoff=cutoff)
    return t, x, y