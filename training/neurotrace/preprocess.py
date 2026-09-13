import numpy as np
from scipy.signal import butter, filtfilt


# Center on the origin, then scale to unit RMS radius
def normalize(x, y):
    x = x - np.mean(x)
    # Center every value of x on the origin 

    y = y - np.mean(y)
    # Center every value of y on the origin

    scale = np.sqrt(np.mean(x**2 + y**2))
    # Find average distance from origin of each point, save it as a scale

    return x / scale, y / scale



def resample_uniform(t, x, y, fs=100.0):
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    if np.any(np.diff(t) <= 0):
    # Checks if any samples are marked as going backward in time

        raise ValueError("timestamps must be strictly increasing")

    t_grid = np.arange(t[0], t[-1], 1.0 / fs)
    # Creates a 1D array that has an equal distance of 1/fs (seconds per sample)
    # that starts at the starting sample time (t[0]) and ends at the last sample

    x_grid = np.interp(t_grid, t, x)
    # Takes the shape of t_grid, then uses the values of t and x to interpolate 
    # an entirely new array of x

    y_grid = np.interp(t_grid, t, y)
    # Takes the shape of t_grid, then uses the values of t and y to interpolate 
    # an entirely new array of y

    return t_grid, x_grid, y_grid



def clean(t, x, y):
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    finite = np.isfinite(t) & np.isfinite(x) & np.isfinite(y)
    # Creates a boolean mask of t, x, and y to keep only the values that
    # are not NaN or inf (overflow number or number from a division by 0 upstream)
    
    t, x, y = t[finite], x[finite], y[finite]
    # Uses the mask to keep only the usable x, y, and t values

    if len(t) == 0:
    #If the length of t is 0, return t, x, and y prematurely to prevent crashing
        
        return t, x, y

    running_max = np.maximum.accumulate(t)
    # Creates an array of the biggest timestamp seen so far from left to right
    
    keep = np.empty(len(t), dtype=bool)
    # Creates an empty array that is the length of t and contains bool values

    keep[0] = True
    # Keep the first sample no matter what

    keep[1:] = t[1:] > running_max[:-1]
    # Checks each value in t that is greater than the running max with the 
    # index before the t value


    return t[keep], x[keep], y[keep]



def trim_stationary(t, x, y, threshold=0.05, window=10):
    if len(t) <= window + 1:
    # If the window is too small compared to the total sample size
        return t, x, y

    dx = x[window:] - x[:-window]
    # Find whether x is moving across a window

    dy = y[window:] - y[:-window]
    # Find whether y is moving across a window

    dt = t[window:] - t[:-window]
    # Find how much time passed across a window

    speed = np.hypot(dx, dy) / dt
    # Find the speed over a window - if it is too small we can ensure that
    # the pen wasn't moving during that window

    moving = speed > threshold * np.median(speed)
    # Checks whether any of the speed values are above the median speed and 
    # creates a boolean array

    if not np.any(moving):
    # If none of the speeds came out to be classified as moving

        return t, x, y

    idx = np.flatnonzero(moving)
    # Provides indexes of where the moving array is true

    first = idx[0]
    # Finds the very first instance of moving

    last = idx[-1] + window
    # Finds the very last instance of moving - any pauses IN BETWEEN 
    # are kept - THEY ARE THE SIGNALS WE WANT


    return t[first:last + 1], x[first:last + 1], y[first:last + 1]


# Function that smoothens out a drawing sample so that jerk doesn't get miscalculated
def low_pass(t, x, y, fs=100.0, cutoff=15.0, order=4):

    b, a = butter(order, cutoff, btype="low", fs=fs)
    # Builds the filter recipe - how to blend each sample with its neighbours

    if len(x) <= 3 * max(len(a), len(b)):
    # If the trace is shorter than the padding filtfilt needs

        raise ValueError(f"trace too short to filter ({len(x)} samples)")

    return t, filtfilt(b, a, x), filtfilt(b, a, y)
    # Filters forwards then backwards so nothing shifts in time


# The one chain everything else calls - THE ORDER MATTERS, the JavaScript
# has to do these same steps in this same order
def preprocess_trace(t, x, y, fs=100.0, cutoff=15.0, trim=True):

    t, x, y = clean(t, x, y)
    # Throw out the broken samples

    if trim:
        t, x, y = trim_stationary(t, x, y)
    # Cut the dead time off each end - before resample so the grid doesn't
    # span the pause, before normalize so the resting samples don't drag the centre

    t, x, y = resample_uniform(t, x, y, fs=fs)
    # Put it on an even 100 Hz grid - every frequency measurement assumes this

    x, y = normalize(x, y)
    # Make tablet units and CSS pixels into the same numbers

    t, x, y = low_pass(t, x, y, fs=fs, cutoff=cutoff)
    # Smooth off anything faster than a hand can move - after resample,
    # because only now do we know the rate is exactly 100

    return t, x, y
