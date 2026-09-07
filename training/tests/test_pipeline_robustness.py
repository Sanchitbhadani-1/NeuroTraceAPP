"""Regression tests for the review's confirmed bugs: spiral_deviation was
dominated by turn-count/start-phase, and an out-of-order sample could
silently truncate a trace.
"""
import numpy as np
import pytest

from neurotrace.preprocess import clean
from neurotrace.pen import spiral_deviation
from neurotrace.synth import create_spiral_synth


def test_spiral_deviation_is_turn_and_phase_invariant():
    _, x_full, y_full = create_spiral_synth(duration=20, fs=240, turns=4)
    baseline = spiral_deviation(x_full, y_full)

    _, x_partial, y_partial = create_spiral_synth(duration=20, fs=240, turns=3.5)
    partial = spiral_deviation(x_partial, y_partial)

    assert partial == pytest.approx(baseline, abs=0.02)


def test_spiral_deviation_still_catches_real_wobble():
    _, x_clean, y_clean = create_spiral_synth(duration=20, fs=240, turns=4)
    clean_dev = spiral_deviation(x_clean, y_clean)

    _, x_wobbly, y_wobbly = create_spiral_synth(duration=20, fs=240, turns=4, tremor_hz=5.5, tremor_amp=40)
    wobbly = spiral_deviation(x_wobbly, y_wobbly)

    assert wobbly > clean_dev * 2


def test_clean_drops_out_of_order_samples():
    """The bug this guards: an out-of-order timestamp used to make
    resample_uniform size its grid from t[-1] - t[0] and silently truncate the
    trace (0.5s -> 0.05s). preprocess.clean discards the backwards sample
    instead — a timestamp that goes backwards is corrupt, not reorderable."""
    t = [0.0, 0.1, 0.2, 0.3, 0.4, 0.05]  # last sample arrives out of order
    x = [0, 1, 2, 3, 4, 0.5]
    y = [0, 1, 2, 3, 4, 0.5]

    t_c, x_c, y_c = clean(t, x, y)

    assert list(t_c) == [0.0, 0.1, 0.2, 0.3, 0.4]
    assert np.all(np.diff(t_c) > 0)
