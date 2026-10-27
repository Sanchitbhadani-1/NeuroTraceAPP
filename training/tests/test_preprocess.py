# TEST_PREPROCESS.PY CHECKS EACH CLEANUP STEP ON MADE UP DRAWINGS
# RUN IT WITH python -m pytest FROM training/

import numpy as np
import pytest

from neurotrace.synth import create_spiral_synth, degrade, FIDELITY_TIERS
from neurotrace.preprocess import (
    clean,
    trim_stationary,
    resample_uniform,
    normalize,
    low_pass,
    preprocess_trace,
)


# Check that clean changes nothing on a drawing with no bad points
def test_clean_is_a_noop_on_clean_input():
    t, x, y = create_spiral_synth()
    ct, cx, cy = clean(t, x, y)

    assert np.array_equal(t, ct)
    assert np.array_equal(x, cx)
    assert np.array_equal(y, cy)


# Check that clean removes a missing value, a repeated time and a time that goes backward
def test_clean_removes_nans_duplicates_and_reversals():

    # Make a short spiral and copy its arrays
    t, x, y = create_spiral_synth(duration=2, fs=50)
    t, x, y = t.copy(), x.copy(), y.copy()

    # Make one x value missing
    x[10] = np.nan

    # Give one point the same time as the point before it
    t[20] = t[19]

    # Give one point an earlier time than the points before it
    t[30] = t[25]

    ct, cx, cy = clean(t, x, y)

    # Check that nothing is missing, time only goes forward, and 3 points were removed
    assert not np.any(np.isnan(cx))
    assert np.all(np.diff(ct) > 0)
    assert len(ct) == len(t) - 3


# Make a spiral with pad still points added at each end, the still points moving by random noise
# Give back the times, x, y and the number of points in the spiral itself
def _pad_with_dead_time(pad=50, noise=0.0, seed=0):

    # Make a 10 second spiral and find its length and time step
    rng = np.random.default_rng(seed)
    t, x, y = create_spiral_synth(duration=10, fs=100)
    n, dt = len(t), t[1] - t[0]

    # Make the still points at the first and last positions, plus noise
    head_x = x[0] + rng.normal(0, noise, pad)
    head_y = y[0] + rng.normal(0, noise, pad)
    tail_x = x[-1] + rng.normal(0, noise, pad)
    tail_y = y[-1] + rng.normal(0, noise, pad)

    # Join the still points to each end and make new evenly spaced times
    return (np.arange(n + 2 * pad) * dt,
            np.concatenate([head_x, x, tail_x]),
            np.concatenate([head_y, y, tail_y]),
            n)


# Check that trim_stationary cuts off the still points at each end
def test_trim_stationary_removes_dead_time():
    t_pad, x_pad, y_pad, n = _pad_with_dead_time(pad=50, noise=0.0)
    tt, _, _ = trim_stationary(t_pad, x_pad, y_pad)

    # Check that it kept the spiral itself
    assert len(tt) >= n - 2

    # Check that it removed the still points, give or take one window of 10 points
    assert len(tt) <= n + 2 * 10


# Check that trim_stationary still cuts off the still points when they move by small random noise
def test_trim_stationary_survives_a_jittering_resting_pen():
    t_pad, x_pad, y_pad, n = _pad_with_dead_time(pad=80, noise=0.3, seed=1)
    tt, _, _ = trim_stationary(t_pad, x_pad, y_pad)

    assert len(tt) >= n - 2
    assert len(tt) <= n + 4 * 10


# Check that trim_stationary keeps almost all of a drawing with no still points
def test_trim_stationary_is_a_noop_on_a_clean_trace():
    t, x, y = create_spiral_synth(duration=10, fs=100)
    tt, _, _ = trim_stationary(t, x, y)

    assert abs(len(tt) - len(t)) <= 2 * 10


# Check that trim_stationary gives back the whole drawing when the pen never moves
def test_trim_stationary_returns_input_when_nothing_moves():

    # Make 100 points that all sit at the same place
    t = np.linspace(0, 1, 100)
    x = np.full(100, 5.0)
    y = np.full(100, 7.0)
    tt, tx, ty = trim_stationary(t, x, y)

    assert len(tt) == len(t)


# Check that normalize centers the drawing on 0 and scales its average distance to 1
def test_normalize_centers_and_scales():
    _, x, y = create_spiral_synth()
    nx, ny = normalize(x, y)

    assert np.mean(nx) == pytest.approx(0.0, abs=1e-9)
    assert np.mean(ny) == pytest.approx(0.0, abs=1e-9)
    assert np.sqrt(np.mean(nx**2 + ny**2)) == pytest.approx(1.0)


# Check that resample_uniform puts a messy drawing back on an even grid close to the original
def test_resample_recovers_a_degraded_trace():

    # Make a spiral and make its timing uneven with some points dropped
    t, x, y = create_spiral_synth()
    dt, dx, dy = degrade(t, x, y, target_fs=120, timing_jitter=0.002,
                         drop_rate=0.02, quantize=0.0, seed=5)

    rt, rx, ry = resample_uniform(dt, dx, dy, fs=100.0)

    # Check that the new times are 0.01 seconds apart
    assert np.allclose(np.diff(rt), 0.01)

    # Check that the new points are within 5 of the original spiral
    truth_x = np.interp(rt, t, x)
    truth_y = np.interp(rt, t, y)
    assert np.max(np.abs(rx - truth_x)) < 5.0
    assert np.max(np.abs(ry - truth_y)) < 5.0


# Check that resample_uniform raises an error when time goes backward
def test_resample_rejects_unsorted_time():
    t = np.array([0.0, 0.1, 0.05, 0.2])
    with pytest.raises(ValueError):
        resample_uniform(t, t, t)


# Check that low_pass keeps a 1 Hz wave and removes a 40 Hz wave
def test_low_pass_keeps_slow_and_removes_fast():

    # Make a slow wave and a fast wave, 100 points per second for 10 seconds
    fs = 100.0
    t = np.arange(0, 10, 1 / fs)
    slow = np.sin(2 * np.pi * 1.0 * t)
    fast = np.sin(2 * np.pi * 40.0 * t)

    # Filter the two waves added together
    _, out, _ = low_pass(t, slow + fast, np.zeros_like(t), fs=fs, cutoff=15.0)

    # Check that the result matches the slow wave, leaving out 50 points at each end
    assert np.max(np.abs(out[50:-50] - slow[50:-50])) < 0.05


# Check that preprocess_trace turns a phone quality drawing into an even, centered and scaled one
def test_preprocess_trace_end_to_end():

    # Make a spiral and make it look like it came from a phone
    t, x, y = create_spiral_synth()
    dt, dx, dy = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=1)

    pt, px, py = preprocess_trace(dt, dx, dy, fs=100.0)

    # Check the time steps, that nothing is missing, and the average distance from the center
    assert np.allclose(np.diff(pt), 0.01)
    assert not np.any(np.isnan(px)) and not np.any(np.isnan(py))
    assert np.sqrt(np.mean(px**2 + py**2)) == pytest.approx(1.0, rel=0.05)


# Check that clean drops a point whose time goes backward, and does not sort it into place
def test_clean_drops_out_of_order_sample_instead_of_sorting():

    # Make 6 points where the last one has an earlier time
    t = [0.0, 0.1, 0.2, 0.3, 0.4, 0.05]
    x = [0, 1, 2, 3, 4, 0.5]
    y = [0, 1, 2, 3, 4, 0.5]

    ct, cx, cy = clean(t, x, y)

    # Check that only the first 5 points are left
    assert list(ct) == [0.0, 0.1, 0.2, 0.3, 0.4]
    assert list(cx) == [0, 1, 2, 3, 4]


# Check that clean removes infinite values as well as missing ones
def test_clean_removes_inf_as_well_as_nan():

    # Make one x value infinite and one minus infinite
    t, x, y = create_spiral_synth(duration=2, fs=50)
    x = x.copy()
    x[7] = np.inf
    x[9] = -np.inf

    ct, cx, cy = clean(t, x, y)

    # Check that every x is a real number and 2 points were removed
    assert np.all(np.isfinite(cx))
    assert len(ct) == len(t) - 2


# Check that low_pass raises an error for a drawing with only 6 points
def test_low_pass_rejects_traces_too_short_to_filter():
    t = np.linspace(0, 0.05, 6)
    with pytest.raises(ValueError):
        low_pass(t, t, t, fs=100.0)
