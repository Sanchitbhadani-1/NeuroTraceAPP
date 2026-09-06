import numpy as np



#Creates a synthetic spiral with parameters for tremor amplitude and tremor frequency
def create_spiral_synth(duration=20, fs=240, turns=4, radius=300, tremor_hz=0.0, tremor_amp=0.0):
    n_samples = duration * fs
    t = np.linspace(0, duration, int(n_samples))
    progress = t / duration

    theta = progress * turns * 2 * np.pi
    r = (progress * radius) + (tremor_amp * np.sin(2 * np.pi * tremor_hz * t))

    x = r * np.cos(theta)
    y = r * np.sin(theta)

    return t, x, y



#Creates a synthetic writing task with parameters for tremor amplitude, tremor frequency, and size trend
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



#Creates a synthetic tapping task with parameters for number of taps, jitter, and rate trend
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



#
FIDELITY_TIERS = {
    "clinical": dict(target_fs=200, timing_jitter=0.0005, drop_rate=0.00, quantize=0.01),
    "tablet":   dict(target_fs=120, timing_jitter=0.0020, drop_rate=0.01, quantize=0.50),
    "phone":    dict(target_fs=60,  timing_jitter=0.0080, drop_rate=0.05, quantize=1.00),
}



def degrade(t, x, y, target_fs=None, timing_jitter=0.0, drop_rate=0.0, quantize=0.0, seed=0):
    rng = np.random.default_rng(seed)

    t = np.asarray(t, dtype=float)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)

    # 1. drop the sample rate
    if target_fs is not None:
        original_fs = 1.0 / np.mean(np.diff(t))
        step = max(1, round(original_fs / target_fs))
        t, x, y = t[::step], x[::step], y[::step]

    # 2. jitter the timestamps
    if timing_jitter > 0:
        t = np.sort(t + rng.normal(0.0, timing_jitter, len(t)))

    # 3. lose samples entirely
    if drop_rate > 0:
        keep = rng.random(len(t)) >= drop_rate
        keep[0] = keep[-1] = True
        t, x, y = t[keep], x[keep], y[keep]

    # 4. quantize the positions
    if quantize > 0:
        x = np.round(x / quantize) * quantize
        y = np.round(y / quantize) * quantize

    return t, x, y