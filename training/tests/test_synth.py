import numpy as np
import pytest

from neurotrace.synth import (
    create_spiral_synth,
    create_writing_synth,
    create_tapping_synth,
)


def test_spiral_shape_and_time_axis():
    t, x, y = create_spiral_synth(duration=10, fs=100)

    assert len(t) == len(x) == len(y) == 1000
    assert t[0] == pytest.approx(0.0)
    assert t[-1] == pytest.approx(10.0)

def test_size_trend_effect():
    _, _, shrinking = create_writing_synth(size_trend=-0.5)
    _, _, growing = create_writing_synth(size_trend=0.5)
    assert peak_ratio(shrinking) < 1.0
    assert peak_ratio(growing) > 1.0


def test_tapping_is_reproducible():
    a_t, a_x, _ = create_tapping_synth(jitter=0.02, seed=7)
    b_t, b_x, _ = create_tapping_synth(jitter=0.02, seed=7)
    c_t, c_x, _ = create_tapping_synth(jitter=0.02, seed=8)

    assert np.array_equal(a_t, b_t)          # same seed -> identical
    assert not np.array_equal(a_t, c_t)      # different seed -> different


def test_tapping_default_rhythm_is_perfect():
    tap_t, tap_x, tap_y = create_tapping_synth()
    gaps = np.diff(tap_t)

    assert len(gaps) == 59
    assert np.allclose(gaps, 0.25)
    assert np.std(gaps) == pytest.approx(0.0, abs=1e-12)