# TEST_SYNTH.PY CHECKS THE MADE UP SPIRALS, WRITING AND TAPPING, AND THE DEGRADE FUNCTION
# RUN IT WITH python -m pytest FROM training/

import numpy as np
import pytest
from scipy.signal import find_peaks

from neurotrace.synth import (
    create_spiral_synth,
    create_writing_synth,
    create_tapping_synth,
    degrade,
    FIDELITY_TIERS,
)


# Find the 5 loop tops in y and give back the last one's height divided by the first one's
def peak_ratio(y):
    peaks, _ = find_peaks(y)
    assert len(peaks) == 5, f"expected 5 loops, found {len(peaks)}"
    return y[peaks[-1]] / y[peaks[0]]


# Give back each point's distance from the center
def radius(x, y):
    return np.hypot(x, y)


# SPIRAL

# Check that a 10 second spiral at 100 points per second has 1000 points from 0 to 10 seconds
def test_spiral_shape_and_time_axis():
    t, x, y = create_spiral_synth(duration=10, fs=100)

    assert len(t) == len(x) == len(y) == 1000
    assert t[0] == pytest.approx(0.0)
    assert t[-1] == pytest.approx(10.0)


# Check that the spiral's distance from the center always grows without tremor, and not with tremor
def test_spiral_radius_monotonic_only_without_tremor():

    # Without tremor
    _, x, y = create_spiral_synth()
    assert np.all(np.diff(radius(x, y)) > 0)

    # With a 5 Hz tremor
    _, xt, yt = create_spiral_synth(tremor_hz=5, tremor_amp=8)
    assert not np.all(np.diff(radius(xt, yt)) > 0)


# WRITING

# Check how much the letters grow or shrink from first to last for each size trend
def test_writing_envelope_magnitudes():

    # Make writing that stays the same size, shrinks, and grows
    _, _, flat = create_writing_synth(size_trend=0.0)
    _, _, pd   = create_writing_synth(size_trend=-0.05)
    _, _, et   = create_writing_synth(size_trend=+0.05)

    # Check the last letter's height over the first letter's height for each one
    assert peak_ratio(flat) == pytest.approx(1.0,    rel=0.01)
    assert peak_ratio(pd)   == pytest.approx(0.8145, rel=0.01)
    assert peak_ratio(et)   == pytest.approx(1.2155, rel=0.01)


# Check that a minus size trend makes the letters shrink and a plus one makes them grow
def test_writing_trend_sign_is_preserved():
    _, _, pd = create_writing_synth(size_trend=-0.05)
    _, _, et = create_writing_synth(size_trend=+0.05)

    assert peak_ratio(pd) < 1.0
    assert peak_ratio(et) > 1.0


# TAPPING

# Check that the same seed gives the same taps and a different seed gives different taps
def test_tapping_is_reproducible():
    a_t, _, _ = create_tapping_synth(jitter=0.02, seed=7)
    b_t, _, _ = create_tapping_synth(jitter=0.02, seed=7)
    c_t, _, _ = create_tapping_synth(jitter=0.02, seed=8)

    assert np.array_equal(a_t, b_t)
    assert not np.array_equal(a_t, c_t)


# Check that the default taps are all exactly 0.25 seconds apart
def test_tapping_default_rhythm_is_perfect():
    tap_t, _, _ = create_tapping_synth()
    gaps = np.diff(tap_t)

    assert len(gaps) == 59
    assert np.allclose(gaps, 0.25)
    assert np.std(gaps) == pytest.approx(0.0, abs=1e-12)


# Check that a minus rate trend makes the last gap about 1.791 times the first
def test_tapping_slows_down():
    tap_t, _, _ = create_tapping_synth(rate_trend=-0.01)
    gaps = np.diff(tap_t)

    assert gaps[-1] / gaps[0] == pytest.approx(1.791, rel=0.01)


# Check that a minus amplitude trend makes the last tap about 0.553 times as far out as the first
def test_tapping_amplitude_shrinks():
    _, tap_x, _ = create_tapping_synth(amp_trend=-0.01)

    assert abs(tap_x[-1]) / abs(tap_x[0]) == pytest.approx(0.553, rel=0.01)


# Check that each tap is on the other side from the tap before it
def test_tapping_alternates_sides():
    _, tap_x, _ = create_tapping_synth()

    assert np.all(np.sign(tap_x[:-1]) != np.sign(tap_x[1:]))


# DEGRADE

# Check that degrade with its default settings changes nothing
def test_degrade_defaults_change_nothing():
    t, x, y = create_spiral_synth()
    dt, dx, dy = degrade(t, x, y)

    assert np.array_equal(t, dt)
    assert np.array_equal(x, dx)
    assert np.array_equal(y, dy)


# Check that the same seed gives the same result and a different seed gives a different one
def test_degrade_is_reproducible():
    t, x, y = create_spiral_synth()
    a_t, _, _ = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=1)
    b_t, _, _ = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=1)
    c_t, _, _ = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=2)

    assert np.array_equal(a_t, b_t)
    assert not np.array_equal(a_t, c_t)


# Check that going from 240 to 60 points per second keeps a quarter of the points
def test_degrade_downsamples():
    t, x, y = create_spiral_synth(fs=240)
    dt, _, _ = degrade(t, x, y, target_fs=60)

    assert len(dt) == len(t) // 4


# Check that quantize rounds every x and y to a step of 0.5
def test_degrade_quantizes():
    t, x, y = create_spiral_synth()
    _, dx, dy = degrade(t, x, y, quantize=0.5)

    assert np.allclose(dx / 0.5, np.round(dx / 0.5))
    assert np.allclose(dy / 0.5, np.round(dy / 0.5))


# Check that the phone settings make the time steps uneven and drop points
def test_degrade_breaks_uniform_sampling():

    # Check that the spiral starts with even time steps
    t, x, y = create_spiral_synth()
    assert np.std(np.diff(t)) == pytest.approx(0.0, abs=1e-12)

    dt, _, _ = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=3)

    # Check that the time steps are now uneven
    assert np.std(np.diff(dt)) > 0.001

    # Check that some points were dropped
    assert len(dt) < len(t)

    # Check that time still only goes forward
    assert np.all(np.diff(dt) > 0)
