import numpy as np
from scipy.signal import butter, filtfilt, find_peaks, welch


# Center on the origin, then scale to unit RMS radius
def normalize(x, y):
    x = np.asarray(x, dtype=float) - np.mean(x)
    y = np.asarray(y, dtype=float) - np.mean(y)
    scale = np.sqrt(np.mean(x**2 + y**2))
    return x / scale, y / scale


def resample_uniform(t, *channels, fs=100):
    """Interpolate one or more channels from raw timestamps onto a uniform fs-Hz grid."""
    t = np.asarray(t, dtype=float)
    n = max(int(round((t[-1] - t[0]) * fs)) + 1, 2)
    t_uniform = np.linspace(t[0], t[-1], n)
    resampled = tuple(np.interp(t_uniform, t, np.asarray(c, dtype=float)) for c in channels)
    return (t_uniform,) + resampled


def lowpass_filter(x, fs, cutoff=15.0, order=4):
    b, a = butter(order, cutoff / (fs / 2), btype="low")
    return filtfilt(b, a, x)


def highpass_filter(x, fs, cutoff=2.0, order=2):
    b, a = butter(order, cutoff / (fs / 2), btype="high")
    return filtfilt(b, a, x)


def speed(x, y, fs):
    dt = 1.0 / fs
    vx, vy = np.gradient(x, dt), np.gradient(y, dt)
    return np.sqrt(vx**2 + vy**2)


def sparc(movement, fs, padlevel=4, fc=10.0, amp_th=0.05):
    """Spectral arc length. Standard smoothness measure (Balasubramanian et al., 2015);
    operates on a speed profile. More negative = less smooth."""
    movement = np.asarray(movement, dtype=float)
    nfft = int(2 ** (np.ceil(np.log2(len(movement))) + padlevel))
    f = np.arange(0, fs, fs / nfft)
    Mf = np.abs(np.fft.fft(movement, nfft))
    Mf = Mf / np.max(Mf)

    fc_idx = np.where(f <= fc)[0]
    f_sel, Mf_sel = f[fc_idx], Mf[fc_idx]
    above_th = np.where(Mf_sel >= amp_th)[0]
    if len(above_th) < 2:
        return np.nan
    f_sel = f_sel[above_th[0]: above_th[-1] + 1]
    Mf_sel = Mf_sel[above_th[0]: above_th[-1] + 1]

    return -np.sum(np.sqrt((np.diff(f_sel) / (f_sel[-1] - f_sel[0])) ** 2 + np.diff(Mf_sel) ** 2))


def log_dimensionless_jerk(velocity, fs):
    """LDJ. Same reference as sparc(); operates on a speed/velocity profile.
    Higher (less negative) = smoother."""
    velocity = np.asarray(velocity, dtype=float)
    peak = np.max(np.abs(velocity))
    if peak == 0:
        return np.nan
    dt = 1.0 / fs
    duration = len(velocity) * dt
    jerk_ = np.diff(velocity, 2) / dt**2
    scale = duration**3 / peak**2
    return -np.log(abs(scale * np.sum(jerk_**2) * dt))


def dominant_frequency(x, fs, band=(3, 8)):
    """Frequency with peak power inside `band`, via Welch PSD."""
    x = np.asarray(x, dtype=float)
    freqs, psd = welch(x, fs=fs, nperseg=min(len(x), fs * 4))
    mask = (freqs >= band[0]) & (freqs <= band[1])
    if not np.any(mask):
        return np.nan
    return float(freqs[mask][np.argmax(psd[mask])])


def band_power(x, fs, band=(4, 6)):
    """Power inside `band`, via Welch PSD integrated with the trapezoid rule."""
    x = np.asarray(x, dtype=float)
    freqs, psd = welch(x, fs=fs, nperseg=min(len(x), fs * 4))
    mask = (freqs >= band[0]) & (freqs <= band[1])
    if not np.any(mask):
        return np.nan
    f_band, p_band = freqs[mask], psd[mask]
    return float(np.sum((p_band[:-1] + p_band[1:]) / 2 * np.diff(f_band)))


def envelope_decline_pct(x, edge_frac=0.1):
    """Percent change in peak amplitude from the first edge_frac of peaks to the last.
    Negative = shrinking. Shared by amplitude_decline (handwriting) and
    tapping_decrement (tapping) — same shape of problem, one implementation.
    # ponytail: peak-picking on raw amplitude; add prominence/min-distance tuning
    # per task if noisy real traces produce spurious peaks.
    """
    x = np.asarray(x, dtype=float)
    centered = x - np.mean(x)
    peaks, _ = find_peaks(np.abs(centered))
    if len(peaks) < 4:
        return np.nan
    amps = np.abs(centered[peaks])
    n_edge = max(1, int(len(amps) * edge_frac))
    start_amp, end_amp = np.mean(amps[:n_edge]), np.mean(amps[-n_edge:])
    if start_amp == 0:
        return np.nan
    return float((end_amp - start_amp) / start_amp * 100)


def spiral_tremor_residual(x, y, fs, highpass_cutoff=2.0):
    """Radial distance from center, high-passed to strip the intended spiral
    growth and leave tremor riding on top of it."""
    r = np.sqrt(x**2 + y**2)
    return highpass_filter(r, fs, cutoff=highpass_cutoff)
