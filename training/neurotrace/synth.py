# SYNTH.PY MAKES MADE UP SPIRAL, WRITING AND TAPPING DRAWINGS
# IT CAN ALSO MAKE A DRAWING LOOK LIKE IT CAME FROM A WORSE DEVICE

import numpy as np


# Make a spiral with a given shake speed and shake size
def create_spiral_synth(duration=20, fs=240, turns=4, radius=300, tremor_hz=0.0, tremor_amp=0.0):

    # Make evenly spaced times and how far through the drawing each one is
    n_samples = duration * fs 
    t = np.linspace(0, duration, int(n_samples))
    progress = t / duration

    # Turn the progress into an angle
    theta = progress * turns * 2 * np.pi

    # Grow the distance from the center at a steady rate and add the shake on top
    r = (progress * radius) + (tremor_amp * np.sin(2 * np.pi * tremor_hz * t)) 

    # Turn each angle and distance into x and y
    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return t, x, y


# Make a row of written "l" loops with a given shake and a size change from loop to loop
def create_writing_synth(duration=20, fs=240, loops=5, width=1000, height=300, lean_ratio=0.4, size_trend=0.0, tremor_hz=0.0, tremor_amp=0.0):

    # Make evenly spaced times
    n_samples = int(duration * fs)
    t = np.linspace(0, duration, n_samples)

    # Find how far through the drawing each time is
    progress = t / duration

    # Turn the progress into an angle that goes round once per loop
    theta = 2 * np.pi * loops * progress

    # Find how many loops have been drawn at each time
    loop_index = loops * progress

    # Grow or shrink each loop by size_trend compared with the one before
    envelope = (1 + size_trend) ** loop_index

    # Find the width of each loop
    lean = lean_ratio * (width / loops)

    # Move steadily to the right and swing side to side with a sine starting at 0
    x = (width * progress) + (lean * envelope * np.sin(theta))

    # Move up and down between 0 and the full height with 1 minus cosine
    y = (height / 2) * envelope * (1 - np.cos(theta))

    # Add the shake to the height
    y = y + tremor_amp * np.sin(2 * np.pi * tremor_hz * t)

    return t, x, y


# Make a list of taps with a given rate, rate change, size change and randomness
def create_tapping_synth(n_taps=60, rate_hz=4.0, separation=400.0, rate_trend=0.0, amp_trend=0.0, jitter=0.0, seed=0):

    rng = np.random.default_rng(seed)

    # Number the taps 0, 1, 2 and so on
    k = np.arange(n_taps)

    # Change the tap rate by rate_trend from one tap to the next
    rate = rate_hz * (1 + rate_trend) ** k

    # Turn taps per second into seconds between taps
    intervals = 1.0 / rate

    # Add randomness to each gap
    intervals = intervals + rng.normal(0.0, jitter, n_taps)

    # Make every gap at least 0.01 seconds
    intervals = np.maximum(intervals, 0.01)

    # Add up the gaps to get the time of each tap
    tap_t = np.cumsum(intervals)

    # Put the taps on the left and right in turn
    side = np.where(k % 2 == 0, -1.0, 1.0)

    # Change how far out each tap lands by amp_trend from one tap to the next
    amplitude = (separation / 2) * (1 + amp_trend) ** k

    # Set each tap's x position, with y always 0
    tap_x = side * amplitude
    tap_y = np.zeros(n_taps)

    return tap_t, tap_x, tap_y


# The settings for three kinds of devices, from best to worst
# target_fs is samples per second, timing_jitter is how far off each time is in seconds,
# drop_rate is the share of samples lost, and quantize is the size positions are rounded to
FIDELITY_TIERS = {
    "clinical": dict(target_fs=200, timing_jitter=0.0005, drop_rate=0.00, quantize=0.01),
    "tablet":   dict(target_fs=120, timing_jitter=0.0020, drop_rate=0.01, quantize=0.50),
    "phone":    dict(target_fs=60,  timing_jitter=0.0080, drop_rate=0.05, quantize=1.00),
}


# Make a drawing look like it came from a worse device
def degrade(t, x, y, target_fs=None, timing_jitter=0.0, drop_rate=0.0, quantize=0.0, seed=0):
    rng = np.random.default_rng(seed)

    # Turn the times and positions into number arrays
    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    # If a target rate is given, lower the samples per second to it
    if target_fs is not None:

        # Find the current samples per second from the average gap
        original_fs = 1.0 / np.mean(np.diff(t))

        # Find how many samples to step over to reach the target rate
        step = max(1, round(original_fs / target_fs))

        # Keep only every step'th sample
        t, x, y = t[::step], x[::step], y[::step]

    # Add random error to each time and put them back in order
    if timing_jitter > 0:
        t = np.sort(t + rng.normal(0.0, timing_jitter, len(t)))

    # Drop samples at random
    if drop_rate > 0:

        # Mark each sample to keep when a random number is at or above the drop rate
        keep = rng.random(len(t)) >= drop_rate

        # Always keep the first and last sample
        keep[0] = keep[-1] = True

        # Keep only the marked samples
        t, x, y = t[keep], x[keep], y[keep]

    # Round the positions
    if quantize > 0:

        # Round x and y to the nearest step of size quantize
        x = np.round(x / quantize) * quantize
        y = np.round(y / quantize) * quantize

    return t, x, y
