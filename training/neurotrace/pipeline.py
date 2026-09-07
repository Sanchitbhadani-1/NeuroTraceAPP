"""Raw trace -> named feature dict. Pipeline order per the timeline: clean,
resample to 100Hz, normalize, low-pass at 15Hz, then derive features.

Preprocessing (clean/resample/normalize/low_pass) lives in preprocess.py and is
shared with the A-track feature primitives in features.py. This module owns only
the orchestration and the named outputs.

Feature names match the model.json featureOrder style in NeuroTrace_Timeline_v7.md
(e.g. "spiral_sparc", "spiral_tremor_4_6", "hw_amplitude_decline_pct").
"""
import numpy as np

from . import preprocess as pre
from . import signal as sig
from .pen import spiral_deviation

TREMOR_BAND = (4, 6)
TREMOR_SEARCH_BAND = (3, 8)

# filtfilt's default padlen is 3 * max(len(a), len(b)); our order=4 butterworth
# needs at least ~13 samples to filter without raising. 16 gives it room.
MIN_SAMPLES = 16

SPIRAL_KEYS = (
    "spiral_sparc",
    "spiral_ldj",
    "spiral_tremor_4_6",
    "spiral_tremor_dominant_hz",
    "spiral_deviation",
)
HANDWRITING_KEYS = ("hw_amplitude_decline_pct",)


def _prepare(t, x, y, fs):
    """clean -> resample -> normalize -> low-pass, or None if the trace is too
    short, non-finite, or never moved. Returns the normalized coordinates
    (tremor rides on these) alongside the filtered ones (speed uses these).

    preprocess.clean only strips NaN, so inf is checked here — it would survive
    cleaning and turn every downstream feature into nan silently.
    """
    t, x, y = pre.clean(t, x, y)
    if len(t) < 2 or not (np.all(np.isfinite(x)) and np.all(np.isfinite(y))):
        return None
    if np.ptp(x) == 0 and np.ptp(y) == 0:
        return None

    t_u, x_u, y_u = pre.resample_uniform(t, x, y, fs=fs)
    if len(t_u) < MIN_SAMPLES:
        return None

    x_n, y_n = pre.normalize(x_u, y_u)
    _, x_f, y_f = pre.low_pass(t_u, x_n, y_n, fs=fs)
    return x_u, y_u, x_n, y_n, x_f, y_f


def extract_spiral_features(t, x, y, fs=100):
    prepared = _prepare(t, x, y, fs)
    if prepared is None:
        return {k: float("nan") for k in SPIRAL_KEYS}
    x_u, y_u, x_n, y_n, x_f, y_f = prepared

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
    prepared = _prepare(t, x, y, fs)
    if prepared is None:
        return {k: float("nan") for k in HANDWRITING_KEYS}
    _, _, _, _, _, y_f = prepared

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
