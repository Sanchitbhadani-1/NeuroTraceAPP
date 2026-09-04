"""Raw trace -> named feature dict. Pipeline order per the timeline: clean,
resample to 100Hz, normalize, low-pass at 15Hz, then derive features.

Feature names match the model.json featureOrder style in NeuroTrace_Timeline_v7.md
(e.g. "spiral_sparc", "spiral_tremor_4_6", "hw_amplitude_decline_pct").
"""
import numpy as np

from . import signal as sig
from .pen import spiral_deviation

TREMOR_BAND = (4, 6)
TREMOR_SEARCH_BAND = (3, 8)

# filtfilt's default padlen is 3 * max(len(a), len(b)); our order=4 butterworth
# needs at least ~13 samples to filter without raising. 16 gives it room.
MIN_SAMPLES = 16


def clean_trace(t, x, y):
    """Sort by time, then drop non-finite samples and duplicate timestamps."""
    t, x, y = np.asarray(t, dtype=float), np.asarray(x, dtype=float), np.asarray(y, dtype=float)
    order = np.argsort(t, kind="stable")
    t, x, y = t[order], x[order], y[order]
    finite = np.isfinite(t) & np.isfinite(x) & np.isfinite(y)
    t, x, y = t[finite], x[finite], y[finite]
    _, first_idx = np.unique(t, return_index=True)
    keep = np.sort(first_idx)
    return t[keep], x[keep], y[keep]


def _degenerate(t, x, y):
    """Too short for the low-pass filter, or no movement at all (normalize()
    would divide by a zero RMS radius)."""
    return len(t) < MIN_SAMPLES or (np.ptp(x) == 0 and np.ptp(y) == 0)


def extract_spiral_features(t, x, y, fs=100):
    t, x, y = clean_trace(t, x, y)
    keys = ("spiral_sparc", "spiral_ldj", "spiral_tremor_4_6", "spiral_tremor_dominant_hz", "spiral_deviation")
    if _degenerate(t, x, y):
        return {k: float("nan") for k in keys}

    _, x_u, y_u = sig.resample_uniform(t, x, y, fs=fs)
    x_n, y_n = sig.normalize(x_u, y_u)
    x_f, y_f = sig.lowpass_filter(x_n, fs), sig.lowpass_filter(y_n, fs)

    spd = sig.speed(x_f, y_f, fs)
    residual = sig.spiral_tremor_residual(x_n, y_n, fs)

    return {
        "spiral_sparc": sig.sparc(spd, fs),
        "spiral_ldj": sig.log_dimensionless_jerk(spd, fs),
        "spiral_tremor_4_6": sig.band_power(residual, fs, band=TREMOR_BAND),
        "spiral_tremor_dominant_hz": sig.dominant_frequency(residual, fs, band=TREMOR_SEARCH_BAND),
        "spiral_deviation": spiral_deviation(x_u, y_u),  # normalizes internally
    }


def extract_handwriting_features(t, x, y, fs=100):
    t, x, y = clean_trace(t, x, y)
    if _degenerate(t, x, y):
        return {"hw_amplitude_decline_pct": float("nan")}

    _, y_u = sig.resample_uniform(t, y, fs=fs)
    y_f = sig.lowpass_filter(y_u, fs)
    return {
        "hw_amplitude_decline_pct": sig.envelope_decline_pct(y_f),
    }


_EXTRACTORS = {
    "spiral": extract_spiral_features,
    "writing": extract_handwriting_features,
}


def features_from_trace(trace, fs=100):
    """The one entry point the week-3 JS/Python parity test drives on both
    sides: takes the trace dict schema/trace.schema.json defines, dispatches
    on trace["task"]."""
    task = trace["task"]
    if task not in _EXTRACTORS:
        raise ValueError(f"no feature extractor for task {task!r} yet")
    samples = trace["samples"]
    t = [s["t"] for s in samples]
    x = [s["x"] for s in samples]
    y = [s["y"] for s in samples]
    return _EXTRACTORS[task](t, x, y, fs=fs)
