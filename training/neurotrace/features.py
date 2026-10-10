import numpy as np
from scipy.signal import butter, filtfilt, welch, find_peaks

from neurotrace.preprocess import preprocess_trace


# spiral geometry________________________

# The ideal spiral, fitted to THIS drawing instead of a saved template
def spiral_fit_residual(x, y, min_turns=1.0):

    theta = np.unwrap(np.arctan2(y, x))
    r = np.hypot(x, y)
    # How far round the pen has gone, and how far out it is

    span = abs(theta[-1] - theta[0]) / (2 * np.pi)
    # Measures the amount of turns in the spiral

    if span < min_turns:
        raise ValueError(f"trace covers only {span:.2f} turns, too little to fit a spiral")

    theta_info = np.column_stack([np.ones(len(theta)), theta, np.cos(theta), np.sin(theta)])
    # Create a 2D matrix with a column of 1s, a column of theta, 
    # and columns of cos(theta) and sin(theta)

    p, *_ = np.linalg.lstsq(theta_info, r, rcond=None)
    # Get only the coefficients of the least squares solution and ignore residuals and rank

    ideal = p[0] + p[1] * theta + p[2] * np.cos(theta) + p[3] * np.sin(theta)
    return r - ideal
    # Return the difference between the actual radius and the fitted (perfect)radius


# How many times the pen properly doubled back
def major_radius_reversals(x, y, min_retrace=0.10):
    r = np.hypot(x, y)

    count = 0
    direction = 0
    extreme = r[0]
    # Remember the furthest the radius has got so far, and which way it's going

    for s in r:
        if direction == 0:
            if s > extreme + min_retrace:
                direction, extreme = 1, s
            elif s < extreme - min_retrace:
                direction, extreme = -1, s
            # Based on where the extreme moved, we can determine direction and set new extreme

        elif direction == 1:
            if s > extreme:
                extreme = s
            elif s < extreme - min_retrace:
                count, direction, extreme = count + 1, -1, s
            # When radius decreases, count it, set new direction, and set new extreme

        else:
            if s < extreme:
                extreme = s
            elif s > extreme + min_retrace:
                count, direction, extreme = count + 1, 1, s
            # When radius increases, count it, set new direction, and set new extreme

    return count

# kinematics ________________________

# Speed, acceleration and jerk all need an evenly sampled trace
def kinematics(t, x, y):

    vx, vy = np.gradient(x, t), np.gradient(y, t)
    # Finds the velocity for each x and y using its nieghbords, and divides by time difference between neighbors

    speed = np.hypot(vx, vy)
    # Finds the magnitude velocity using hypotneuse

    ax, ay = np.gradient(vx, t), np.gradient(vy, t)
    # Same thing as the velocity equation, but takes the derivative of velocity

    accel = np.hypot(ax, ay)
    # Finds magnitude acceleration using hypotneuse

    jx, jy = np.gradient(ax, t), np.gradient(ay, t)
    # Measures jerk (derivative of acceleration) using neighbors and divides by time difference between neighbors

    jerk = np.hypot(jx, jy)
    # Finds magnitude jerk using hypotneuse
    
    return speed, accel, jerk


# Münster F12 and F13
def speed_features(speed):
    return {
        "mean_speed": float(np.mean(speed)),
        "std_speed":  float(np.std(speed)),
    }


# Münster F2, F3 and F4
def deviation_features(d):
    return {
        "max_deviation":  float(np.max(np.abs(d))),
        "mean_deviation": float(np.mean(np.abs(d))),
        "std_deviation":  float(np.std(d)),
        # std uses the SIGNED values - spread around the line, not spread of sizes
    }


# --- smoothness ------------------------------------------------------

# One smoothness score - closer to zero is smoother
def log_dimensionless_jerk(t, speed, jerk):

    duration = t[-1] - t[0]
    dt = np.mean(np.diff(t))

    jerk_integral = np.sum(jerk ** 2) * dt
    # Total jerk over the whole drawing

    v_peak = np.max(speed)

    return float(-np.log((duration ** 3 / v_peak ** 2) * jerk_integral))
    # Scaling by duration and peak speed makes size and time cancel out, so
    # the number compares across people and devices


# Spectral arc length (Balasubramanian 2015) - more negative is less smooth
def sparc(speed, fs, padlevel=4, fc=10.0, amp_th=0.05):
    # DO NOT simplify - padlevel, fc and amp_th are part of the published
    # definition, and any number we compare to a paper depends on them

    speed = np.asarray(speed, dtype=float)

    nfft = int(2 ** (np.ceil(np.log2(len(speed))) + padlevel))
    f = np.arange(0, fs, fs / nfft)
    Mf = np.abs(np.fft.fft(speed, nfft))
    Mf = Mf / np.max(Mf)
    # The speed profile's frequency content, scaled to a peak of 1

    sel = f <= fc
    f_sel, Mf_sel = f[sel], Mf[sel]
    # Keep only below the cutoff

    above = np.where(Mf_sel >= amp_th)[0]
    if len(above) < 2:
        return float("nan")
    f_sel = f_sel[above[0]:above[-1] + 1]
    Mf_sel = Mf_sel[above[0]:above[-1] + 1]
    # Trim to the part that is actually above the noise floor

    arc = np.sqrt((np.diff(f_sel) / (f_sel[-1] - f_sel[0])) ** 2 + np.diff(Mf_sel) ** 2)
    return float(-np.sum(arc))
    # Length of that curve - a smooth movement has a compact spectrum and a
    # short curve, a jerky one has a spread out spectrum and a long one


# --- tremor ----------------------------------------------------------

# Strips the spiral out of the radius and leaves the wobble riding on it
def tremor_residual(x, y, fs, cutoff=2.0):

    r = np.hypot(x, y)

    b, a = butter(2, cutoff, btype="high", fs=fs)
    return filtfilt(b, a, r)
    # High-pass, so the spiral's slow growth (under 1 Hz) drops out


# Splits a signal into how much power sits at each frequency
def _welch(sig, fs):
    nperseg = min(len(sig), int(fs * 4))
    return welch(sig, fs=fs, nperseg=nperseg)
    # Averages over 4 second chunks - far less noisy than one big FFT


# How much wobble sits inside a frequency band
def band_power(sig, fs, band):

    freqs, psd = _welch(sig, fs)

    m = (freqs >= band[0]) & (freqs <= band[1])
    f, p = freqs[m], psd[m]
    # Keep only the frequencies inside the band

    if len(f) < 2:
        return float("nan")

    return float(np.sum((p[:-1] + p[1:]) / 2 * np.diff(f)))
    # Area under the curve across that band


# The single strongest wobble frequency inside a band
def dominant_frequency(sig, fs, band=(3.0, 12.0)):

    freqs, psd = _welch(sig, fs)
    m = (freqs >= band[0]) & (freqs <= band[1])

    if not np.any(m):
        return float("nan")

    return float(freqs[m][np.argmax(psd[m])])
    # Whichever frequency in the band has the most power


# --- writing ---------------------------------------------------------

# Height of every letter in a writing trace
def loop_heights(y, min_prominence_frac=0.2):

    prominence = min_prominence_frac * np.ptp(y)
    # Prominence = height above the surrounding baseline, so it does not care
    # where normalize put the baseline. The fraction ignores tremor wiggles

    _, props = find_peaks(y, prominence=prominence)
    return props["prominences"]


# How fast the letters shrink or grow - THE PD vs ET feature
def amplitude_trend(heights):

    heights = np.asarray(heights, dtype=float)
    heights = heights[heights > 0]

    if len(heights) < 3:
        return float("nan")

    k = np.arange(len(heights))

    slope = np.polyfit(k, np.log(heights), 1)[0]
    # Fit a line through log(height) - a slope means each loop is a fixed
    # fraction of the last

    return float(np.exp(slope) - 1.0)
    # Same units as size_trend in the generator. SIGNED - negative shrinks
    # (PD), positive grows (ET). NEVER wrap this in abs()


# --- assembly --------------------------------------------------------
# Every extract_* takes a PREPROCESSED trace, except tapping, which is
# discrete events and is never resampled.
# KEY ORDER = featureOrder in model.json. Append only, never rename after
# the Sept 20 freeze, or the weights land on the wrong features.

def extract_spiral_features(t, x, y, fs=100.0):

    d = spiral_fit_residual(x, y)
    # No saved template - pen.reference_spiral only draws the on-screen guide
    # now, so changing that guide can never move a feature

    speed, accel, jerk = kinematics(t, x, y)
    residual = tremor_residual(x, y, fs)

    f = {}
    f["spiral_duration"] = float(t[-1] - t[0])                      # F11

    for k, v in deviation_features(d).items():                      # F2-F4
        f["spiral_" + k] = v

    f["spiral_major_reversals"] = major_radius_reversals(x, y)      # F5, fixed

    for k, v in speed_features(speed).items():                      # F12-F13
        f["spiral_" + k] = v

    f["spiral_ldlj"] = log_dimensionless_jerk(t, speed, jerk)
    f["spiral_sparc"] = sparc(speed, fs)

    f["spiral_tremor_4_6"] = band_power(residual, fs, (4.0, 6.0))
    # 4-6 Hz is Parkinsonian territory

    f["spiral_tremor_6_12"] = band_power(residual, fs, (6.0, 12.0))
    # 6-12 Hz is essential tremor territory

    f["spiral_tremor_dominant_hz"] = dominant_frequency(residual, fs)

    return f


def extract_writing_features(t, x, y, fs=100.0):

    speed, accel, jerk = kinematics(t, x, y)
    heights = loop_heights(y)

    f = {}
    f["writing_duration"] = float(t[-1] - t[0])
    f["writing_n_loops"] = int(len(heights))

    f["writing_amplitude_trend"] = amplitude_trend(heights)
    # The one that separates PD from ET - keep the sign

    for k, v in speed_features(speed).items():
        f["writing_" + k] = v

    f["writing_ldlj"] = log_dimensionless_jerk(t, speed, jerk)
    f["writing_sparc"] = sparc(speed, fs)

    return f


def extract_tapping_features(tap_t, tap_x, tap_y=None):

    tap_t = np.asarray(tap_t, dtype=float)
    tap_x = np.asarray(tap_x, dtype=float)

    gaps = np.diff(tap_t)
    # Gaps BETWEEN taps - one shorter than tap_t, because the time before the
    # first tap is a reaction delay, not a rhythm

    k = np.arange(len(gaps))

    f = {}
    f["tap_count"] = int(len(tap_t))
    f["tap_duration"] = float(tap_t[-1] - tap_t[0])
    f["tap_rate"] = float(len(gaps) / f["tap_duration"])            # taps per second
    f["tap_rhythm_sd"] = float(np.std(gaps))                        # seconds

    f["tap_rhythm_cv"] = float(np.std(gaps) / np.mean(gaps))
    # Same thing as a fraction of the rate, so it compares across people

    slope = np.polyfit(k, np.log(gaps), 1)[0]
    f["tap_rate_trend"] = float(np.exp(-slope) - 1.0)
    # Gaps stretch as the person slows, so the slope is flipped. SIGNED -
    # negative means slowing down

    f["tap_amplitude_trend"] = amplitude_trend(np.abs(tap_x))
    # SIGNED - negative means the taps stopped reaching the targets

    return f


_EXTRACTORS = {
    "spiral":  extract_spiral_features,
    "writing": extract_writing_features,
}


# The front door - takes the trace dict the app produces and returns features
def features_from_trace(trace, fs=100.0):
    # This is what the Week 3 parity test runs on both the Python and JS sides

    task = trace["task"]
    samples = trace["samples"]
    t = np.array([s["t"] for s in samples], dtype=float)
    x = np.array([s["x"] for s in samples], dtype=float)
    y = np.array([s["y"] for s in samples], dtype=float)

    if task == "tap":
        return extract_tapping_features(t, x, y)
        # No preprocessing - taps are events, you cannot resample them.
        # ASSUMPTION: each sample in a tap trace is one tap

    if task not in _EXTRACTORS:
        raise ValueError(f"no feature extractor for task {task!r}")

    t, x, y = preprocess_trace(t, x, y, fs=fs)
    return _EXTRACTORS[task](t, x, y, fs=fs)
