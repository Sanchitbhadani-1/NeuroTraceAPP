import numpy as np

def create_spiral_synth(duration=20, fs=240, turns=4, radius=300, tremor_hz=0.0, tremor_amp=0.0):
    n_samples = duration * fs
    t = np.linspace(0, duration, int(n_samples))
    progress = t / duration

    theta = progress * turns * 2 * np.pi
    r = (progress * radius) + (tremor_amp * np.sin(2 * np.pi * tremor_hz * t))

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return t, x, y

def create_writing_synth(duration=20, fs=240, loops=5, width=1000, height=300, lean_ratio=0.4, size_trend=0.0, tremor_hz=0.0, tremor_amp=0.0):
    n_samples = int(duration * fs)
    t = np.linspace(0, duration, n_samples)
    progress = t / duration

    theta = 2 * np.pi * loops * progress

    loop_index = loops * progress

    envelope = (1 + size_trend) ** loop_index

    lean = lean_ratio * (width / loops)

    x = (width * progress) + (lean * envelope * np.sin(theta))
    y = (height / 2) * envelope * (1 - np.cos(theta))

    y = y + tremor_amp * np.sin(2 * np.pi * tremor_hz * t)

    return t, x, y


def create_tapping_synth(n_taps=60, rate_hz=4.0, separation=400.0, rate_trend=0.0, amp_trend=0.0, jitter=0.0, seed=0):
    
    rng = np.random.default_rng(seed)

    k = np.arange(n_taps)

    rate = rate_hz * (1 + rate_trend) ** k
    intervals = 1.0 / rate
    intervals = intervals + rng.normal(0.0, jitter, n_taps)
    intervals = np.maximum(intervals, 0.01)
    tap_t = np.cumsum(intervals)

    side = np.where(k % 2 == 0, -1.0, 1.0)
    amplitude = (separation / 2) * (1 + amp_trend) ** k
    tap_x = side * amplitude
    tap_y = np.zeros(n_taps)

    return tap_t, tap_x, tap_y