"""Week 1 done-when: A's features pass synthetic tests.
Inject a known 5.5 Hz tremor -> confirm ~5.5 Hz comes back.
Generate handwriting shrinking 30% -> confirm ~-30% comes back.
"""

import pytest

from neurotrace.synth import create_spiral_synth, create_handwriting_synth
from neurotrace.pipeline import extract_spiral_features, extract_handwriting_features

FS = 100


def test_tremor_frequency_recovered():
    t, x, y = create_spiral_synth(duration=20, fs=240, tremor_hz=5.5, tremor_amp=8)
    features = extract_spiral_features(t, x, y, fs=FS)
    assert features["spiral_tremor_dominant_hz"] == pytest.approx(5.5, abs=0.5)


def test_no_injected_tremor_stays_quiet():
    t, x, y = create_spiral_synth(duration=20, fs=240, tremor_hz=0.0, tremor_amp=0.0)
    tremor_features = extract_spiral_features(t, x, y, fs=FS)
    baseline_band_power = tremor_features["spiral_tremor_4_6"]

    t2, x2, y2 = create_spiral_synth(duration=20, fs=240, tremor_hz=5.5, tremor_amp=8)
    tremor_injected = extract_spiral_features(t2, x2, y2, fs=FS)
    assert tremor_injected["spiral_tremor_4_6"] > baseline_band_power


def test_amplitude_decline_recovered():
    t, x, y = create_handwriting_synth(duration=10, fs=100, shrink_pct=0.30)
    features = extract_handwriting_features(t, x, y, fs=FS)
    assert features["hw_amplitude_decline_pct"] == pytest.approx(-30, abs=5)


def test_no_shrink_stays_flat():
    t, x, y = create_handwriting_synth(duration=10, fs=100, shrink_pct=0.0)
    features = extract_handwriting_features(t, x, y, fs=FS)
    assert features["hw_amplitude_decline_pct"] == pytest.approx(0, abs=5)
