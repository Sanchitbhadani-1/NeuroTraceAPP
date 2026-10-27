# FEATURES.PY TURNS A CLEANED DRAWING INTO THE NUMBERS THE MODEL USES
# IT HAS THE 12 SPIRAL NUMBERS, PLUS NUMBERS FOR WRITING AND TAPPING

import numpy as np
from scipy.signal import butter, filtfilt, welch, find_peaks

from neurotrace.preprocess import preprocess_trace


# SPIRAL SHAPE

# Fit an ideal spiral to this drawing and give back how far each point is from it
def spiral_fit_residual(x, y, min_turns=1.0):

    # Find the angle around the center and the distance from the center for each point
    theta = np.unwrap(np.arctan2(y, x))
    r = np.hypot(x, y)

    # Count how many turns the drawing makes
    span = abs(theta[-1] - theta[0]) / (2 * np.pi)

    # Stop if the drawing makes fewer turns than min_turns
    if span < min_turns:
        raise ValueError(f"trace covers only {span:.2f} turns, too little to fit a spiral")

    # Build a table with a column of 1s, the angle, the cosine of the angle and the sine of the angle
    theta_info = np.column_stack([np.ones(len(theta)), theta, np.cos(theta), np.sin(theta)])

    # Find the best fit numbers for that table, keeping only the numbers
    p, *_ = np.linalg.lstsq(theta_info, r, rcond=None)

    # Give back the real distance minus the fitted distance at each point
    ideal = p[0] + p[1] * theta + p[2] * np.cos(theta) + p[3] * np.sin(theta)
    return r - ideal


# Count how many times the distance from the center turns around by more than min_retrace
def major_radius_reversals(x, y, min_retrace=0.10):
    r = np.hypot(x, y)

    # Start with no turns, no direction, and the first distance as the furthest point
    count = 0
    direction = 0
    extreme = r[0]

    for s in r:

        # With no direction yet, pick one once the distance moves more than min_retrace
        if direction == 0:
            if s > extreme + min_retrace:
                direction, extreme = 1, s
            elif s < extreme - min_retrace:
                direction, extreme = -1, s

        # Going out, keep the furthest point, and count a turn when it comes back in by more than min_retrace
        elif direction == 1:
            if s > extreme:
                extreme = s
            elif s < extreme - min_retrace:
                count, direction, extreme = count + 1, -1, s

        # Going in, keep the closest point, and count a turn when it goes back out by more than min_retrace
        else:
            if s < extreme:
                extreme = s
            elif s > extreme + min_retrace:
                count, direction, extreme = count + 1, 1, s

    return count


# SPEED AND MOVEMENT

# Find the speed, acceleration and jerk at each point
def kinematics(t, x, y):

    # Find the x and y speed at each point
    vx, vy = np.gradient(x, t), np.gradient(y, t)

    # Combine them into one speed
    speed = np.hypot(vx, vy)

    # Find the x and y acceleration from the speeds
    ax, ay = np.gradient(vx, t), np.gradient(vy, t)

    # Combine them into one acceleration
    accel = np.hypot(ax, ay)

    # Find the x and y jerk from the accelerations
    jx, jy = np.gradient(ax, t), np.gradient(ay, t)

    # Combine them into one jerk
    jerk = np.hypot(jx, jy)

    return speed, accel, jerk


# Give back the average speed and how much the speed varies
def speed_features(speed):
    return {
        "mean_speed": float(np.mean(speed)),
        "std_speed":  float(np.std(speed)),
    }


# Give back the largest and average distance from the ideal spiral, and how much it varies
def deviation_features(d):
    return {
        "max_deviation":  float(np.max(np.abs(d))),
        "mean_deviation": float(np.mean(np.abs(d))),

        # Measure the spread of the signed distances
        "std_deviation":  float(np.std(d)),
    }


# SMOOTHNESS

# Give back one smoothness score from the jerk, closer to 0 is smoother
def log_dimensionless_jerk(t, speed, jerk):

    # Find how long the drawing lasts and the average time step
    duration = t[-1] - t[0]
    dt = np.mean(np.diff(t))

    # Add up the squared jerk over the whole drawing
    jerk_integral = np.sum(jerk ** 2) * dt

    # Find the top speed
    v_peak = np.max(speed)

    # Scale the jerk by the duration and top speed, then take the negative log
    return float(-np.log((duration ** 3 / v_peak ** 2) * jerk_integral))


# Give back the spectral arc length of the speed, more negative is less smooth
def sparc(speed, fs, padlevel=4, fc=10.0, amp_th=0.05):

    speed = np.asarray(speed, dtype=float)

    # Find how strong each frequency is in the speed, scaled so the top is 1
    nfft = int(2 ** (np.ceil(np.log2(len(speed))) + padlevel))
    f = np.arange(0, fs, fs / nfft)
    Mf = np.abs(np.fft.fft(speed, nfft))
    Mf = Mf / np.max(Mf)

    # Keep only the frequencies at or below fc
    sel = f <= fc
    f_sel, Mf_sel = f[sel], Mf[sel]

    # Keep only the range from the first to the last frequency at or above amp_th, or give back NaN if fewer than 2
    above = np.where(Mf_sel >= amp_th)[0]
    if len(above) < 2:
        return float("nan")
    f_sel = f_sel[above[0]:above[-1] + 1]
    Mf_sel = Mf_sel[above[0]:above[-1] + 1]

    # Give back the negative length of that curve
    arc = np.sqrt((np.diff(f_sel) / (f_sel[-1] - f_sel[0])) ** 2 + np.diff(Mf_sel) ** 2)
    return float(-np.sum(arc))


# TREMOR

# Take out the slow growth of the spiral and leave only the fast shaking in the distance from the center
def tremor_residual(x, y, fs, cutoff=2.0):

    r = np.hypot(x, y)

    # Remove everything slower than cutoff times per second from the distance
    b, a = butter(2, cutoff, btype="high", fs=fs)
    return filtfilt(b, a, r)


# Find how much power the signal has at each frequency, using 4 second chunks
def _welch(sig, fs):
    nperseg = min(len(sig), int(fs * 4))
    return welch(sig, fs=fs, nperseg=nperseg)


# Give back how much shaking power is inside a frequency band
def band_power(sig, fs, band):

    freqs, psd = _welch(sig, fs)

    # Keep only the frequencies inside the band
    m = (freqs >= band[0]) & (freqs <= band[1])
    f, p = freqs[m], psd[m]

    # Give back NaN if fewer than 2 frequencies are inside
    if len(f) < 2:
        return float("nan")

    # Give back the area under the power curve across the band
    return float(np.sum((p[:-1] + p[1:]) / 2 * np.diff(f)))


# Give back the strongest shaking frequency inside a band
def dominant_frequency(sig, fs, band=(3.0, 12.0)):

    # Find the power at each frequency and mark the ones inside the band
    freqs, psd = _welch(sig, fs)
    m = (freqs >= band[0]) & (freqs <= band[1])

    # Give back NaN if no frequencies are inside
    if not np.any(m):
        return float("nan")

    # Give back the frequency in the band with the most power
    return float(freqs[m][np.argmax(psd[m])])


# WRITING

# Give back the height of every letter in a writing drawing
def loop_heights(y, min_prominence_frac=0.2):

    # Only count peaks that stand up at least 20% of the full height range
    prominence = min_prominence_frac * np.ptp(y)

    # Find the peaks and give back how far each one stands up
    _, props = find_peaks(y, prominence=prominence)
    return props["prominences"]


# Give back how fast the letters shrink or grow from one to the next, negative means shrinking
def amplitude_trend(heights):

    # Keep only heights above 0
    heights = np.asarray(heights, dtype=float)
    heights = heights[heights > 0]

    # Give back NaN if there are fewer than 3 heights
    if len(heights) < 3:
        return float("nan")

    # Number the letters 0, 1, 2 and so on
    k = np.arange(len(heights))

    # Fit a straight line through the log of the heights and take its slope
    slope = np.polyfit(k, np.log(heights), 1)[0]

    # Turn the slope into the change from one letter to the next
    return float(np.exp(slope) - 1.0)


# PUTTING IT TOGETHER

# Give back the 12 spiral numbers for a cleaned spiral drawing, in the order the model reads them
def extract_spiral_features(t, x, y, fs=100.0):

    # Find how far each point is from the fitted spiral
    d = spiral_fit_residual(x, y)

    # Find the speed, acceleration, jerk and shaking
    speed, accel, jerk = kinematics(t, x, y)
    residual = tremor_residual(x, y, fs)

    # Add how long the drawing lasts
    f = {}
    f["spiral_duration"] = float(t[-1] - t[0])

    # Add the distance from the ideal spiral numbers
    for k, v in deviation_features(d).items():
        f["spiral_" + k] = v

    # Add how many times the pen turns back
    f["spiral_major_reversals"] = major_radius_reversals(x, y)

    # Add the speed numbers
    for k, v in speed_features(speed).items():
        f["spiral_" + k] = v

    # Add the two smoothness scores
    f["spiral_ldlj"] = log_dimensionless_jerk(t, speed, jerk)
    f["spiral_sparc"] = sparc(speed, fs)

    # Add the shaking power from 4 to 6 times per second
    f["spiral_tremor_4_6"] = band_power(residual, fs, (4.0, 6.0))

    # Add the shaking power from 6 to 12 times per second
    f["spiral_tremor_6_12"] = band_power(residual, fs, (6.0, 12.0))

    # Add the strongest shaking frequency
    f["spiral_tremor_dominant_hz"] = dominant_frequency(residual, fs)

    return f


# Give back the numbers for a cleaned writing drawing
def extract_writing_features(t, x, y, fs=100.0):

    # Find the speed, acceleration, jerk and letter heights
    speed, accel, jerk = kinematics(t, x, y)
    heights = loop_heights(y)

    # Add how long the drawing lasts and how many letters it has
    f = {}
    f["writing_duration"] = float(t[-1] - t[0])
    f["writing_n_loops"] = int(len(heights))

    # Add how fast the letters shrink or grow, keeping the sign
    f["writing_amplitude_trend"] = amplitude_trend(heights)

    # Add the speed numbers
    for k, v in speed_features(speed).items():
        f["writing_" + k] = v

    # Add the two smoothness scores
    f["writing_ldlj"] = log_dimensionless_jerk(t, speed, jerk)
    f["writing_sparc"] = sparc(speed, fs)

    return f


# Give back the numbers for a list of taps
def extract_tapping_features(tap_t, tap_x, tap_y=None):

    # Turn the tap times and x positions into number arrays
    tap_t = np.asarray(tap_t, dtype=float)
    tap_x = np.asarray(tap_x, dtype=float)

    # Find the time between each tap and the next
    gaps = np.diff(tap_t)

    # Number the gaps 0, 1, 2 and so on
    k = np.arange(len(gaps))

    # Add the tap count and how long the tapping lasts
    f = {}
    f["tap_count"] = int(len(tap_t))
    f["tap_duration"] = float(tap_t[-1] - tap_t[0])

    # Add the taps per second
    f["tap_rate"] = float(len(gaps) / f["tap_duration"])

    # Add how much the gaps vary, in seconds
    f["tap_rhythm_sd"] = float(np.std(gaps))

    # Add how much the gaps vary as a share of the average gap
    f["tap_rhythm_cv"] = float(np.std(gaps) / np.mean(gaps))

    # Fit a line through the log of the gaps and flip its slope, negative means slowing down
    slope = np.polyfit(k, np.log(gaps), 1)[0]
    f["tap_rate_trend"] = float(np.exp(-slope) - 1.0)

    # Add how fast the tap distances shrink or grow, negative means shrinking
    f["tap_amplitude_trend"] = amplitude_trend(np.abs(tap_x))

    return f


# The function to run for each drawing task
_EXTRACTORS = {
    "spiral":  extract_spiral_features,
    "writing": extract_writing_features,
}


# Take a drawing in the shape the app makes and give back its numbers
def features_from_trace(trace, fs=100.0):

    # Pull the task and the times and positions out of the drawing
    task = trace["task"]
    samples = trace["samples"]
    t = np.array([s["t"] for s in samples], dtype=float)
    x = np.array([s["x"] for s in samples], dtype=float)
    y = np.array([s["y"] for s in samples], dtype=float)

    # Treat each sample of a tap drawing as one tap and skip the cleanup
    if task == "tap":
        return extract_tapping_features(t, x, y)

    # Stop if there is no function for this task
    if task not in _EXTRACTORS:
        raise ValueError(f"no feature extractor for task {task!r}")

    # Clean up the drawing, then run the function for its task
    t, x, y = preprocess_trace(t, x, y, fs=fs)
    return _EXTRACTORS[task](t, x, y, fs=fs)
