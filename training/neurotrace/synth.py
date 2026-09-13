import numpy as np



#Creates a synthetic spiral with parameters for tremor amplitude and tremor frequency
def create_spiral_synth(duration=20, fs=240, turns=4, radius=300, tremor_hz=0.0, tremor_amp=0.0):

    n_samples = duration * fs 
    t = np.linspace(0, duration, int(n_samples))
    progress = t / duration

    theta = progress * turns * 2 * np.pi

    r = (progress * radius) + (tremor_amp * np.sin(2 * np.pi * tremor_hz * t)) 
    # Radius is increasing constantly with additional tremor based on hz and amplitude

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return t, x, y



#Creates a synthetic writing task with parameters for tremor amplitude, tremor frequency, and size trend
def create_writing_synth(duration=20, fs=240, loops=5, width=1000, height=300, lean_ratio=0.4, size_trend=0.0, tremor_hz=0.0, tremor_amp=0.0):

    n_samples = int(duration * fs)
    t = np.linspace(0, duration, n_samples)

    progress = t / duration
    # Progresss in terms of time

    theta = 2 * np.pi * loops * progress

    loop_index = loops * progress
    # Progress in terms of loops

    envelope = (1 + size_trend) ** loop_index
    # The trend at which size decreases or increases

    lean = lean_ratio * (width / loops)
    # Width of each "l"

    x = (width * progress) + (lean * envelope * np.sin(theta))
    # Uses sin since sin starts at 0

    y = (height / 2) * envelope * (1 - np.cos(theta))
    # Uses cos since 1 - cos since that allows for a range of 0 - 2.

    y = y + tremor_amp * np.sin(2 * np.pi * tremor_hz * t)
    # Additional termor can be added based on amp and frequency

    return t, x, y



#Creates a synthetic tapping task with parameters for number of taps, jitter, and rate trend
def create_tapping_synth(n_taps=60, rate_hz=4.0, separation=400.0, rate_trend=0.0, amp_trend=0.0, jitter=0.0, seed=0):

    rng = np.random.default_rng(seed)

    k = np.arange(n_taps)
    # Creates an array from 0 - n_taps

    rate = rate_hz * (1 + rate_trend) ** k
    # Trend in speed of rate a person taps at

    # When each tap happens
    intervals = 1.0 / rate
    # Converts rate (taps per sec) into intervals (sec per tap)

    intervals = intervals + rng.normal(0.0, jitter, n_taps)
    # Adding randomness to each tap

    intervals = np.maximum(intervals, 0.01)
    # Forces each interval to be at minimum 0.01 sec per tap

    tap_t = np.cumsum(intervals)
    # Adds the cumalitive intervals across the entire test

    # Where each tap happens
    side = np.where(k % 2 == 0, -1.0, 1.0)
    # Decides which side a tap happens

    amplitude = (separation / 2) * (1 + amp_trend) ** k
    # Spreads out taps either more or less into a direction

    tap_x = side * amplitude
    tap_y = np.zeros(n_taps)

    return tap_t, tap_x, tap_y



# Fidelity tiers that show progressively worse equipment
FIDELITY_TIERS = {
    "clinical": dict(target_fs=200, timing_jitter=0.0005, drop_rate=0.00, quantize=0.01),
    "tablet":   dict(target_fs=120, timing_jitter=0.0020, drop_rate=0.01, quantize=0.50),
    "phone":    dict(target_fs=60,  timing_jitter=0.0080, drop_rate=0.05, quantize=1.00),
}
# Target fs = hertz
# Timing jitter = how far a sample is in time from when it was ACTUALLY sampled
# Drop rate = how many samples were dropped by accident
# Quantize = rounding limits by equipment


def degrade(t, x, y, target_fs=None, timing_jitter=0.0, drop_rate=0.0, quantize=0.0, seed=0):
    rng = np.random.default_rng(seed)

    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    # Drop the sample rate
    if target_fs is not None:
    # If a target_fs exists

        original_fs = 1.0 / np.mean(np.diff(t))
        # Averages gaps between intervals and turns it into OG hz

        step = max(1, round(original_fs / target_fs))
        # Finds how many samples to skip to get to the target hz

        t, x, y = t[::step], x[::step], y[::step]

    # Jitter the timestamps
    if timing_jitter > 0:
        t = np.sort(t + rng.normal(0.0, timing_jitter, len(t)))
        # Adds a jitter to timestamps

    # Lose samples entirely
    if drop_rate > 0:
        keep = rng.random(len(t)) >= drop_rate
        # Create a boolean mask by making an array of probabilities
        # and comparing it to drop rate

        keep[0] = keep[-1] = True
        # Force first and last sample to be kept

        t, x, y = t[keep], x[keep], y[keep]
        # Apply the mask

    # Quantize the positions
    if quantize > 0:

        # Round x and y by quantize factor
        x = np.round(x / quantize) * quantize
        y = np.round(y / quantize) * quantize

    return t, x, y