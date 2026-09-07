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


def test_clean_is_a_noop_on_clean_input():
    t, x, y = create_spiral_synth()
    ct, cx, cy = clean(t, x, y)

    assert np.array_equal(t, ct)
    assert np.array_equal(x, cx)
    assert np.array_equal(y, cy)


def test_clean_removes_nans_duplicates_and_reversals():
    t, x, y = create_spiral_synth(duration=2, fs=50)
    t, x, y = t.copy(), x.copy(), y.copy()

    x[10] = np.nan          # a missing coordinate
    t[20] = t[19]           # a duplicated timestamp
    t[30] = t[25]           # an out-of-order event

    ct, cx, cy = clean(t, x, y)

    assert not np.any(np.isnan(cx))
    assert np.all(np.diff(ct) > 0)
    assert len(ct) == len(t) - 3


def test_trim_stationary_removes_dead_time():
    t, x, y = create_spiral_synth(duration=10, fs=100)
    n, pad = len(t), 50
    dt = t[1] - t[0]

    t_pad = np.arange(n + 2 * pad) * dt
    x_pad = np.concatenate([np.full(pad, x[0]), x, np.full(pad, x[-1])])
    y_pad = np.concatenate([np.full(pad, y[0]), y, np.full(pad, y[-1])])

    tt, tx, ty = trim_stationary(t_pad, x_pad, y_pad)

    assert abs(len(tt) - n) <= 2


def test_normalize_centres_and_scales():
    _, x, y = create_spiral_synth()
    nx, ny = normalize(x, y)

    assert np.mean(nx) == pytest.approx(0.0, abs=1e-9)
    assert np.mean(ny) == pytest.approx(0.0, abs=1e-9)
    assert np.sqrt(np.mean(nx**2 + ny**2)) == pytest.approx(1.0)


def test_resample_recovers_a_degraded_trace():
    t, x, y = create_spiral_synth()
    dt, dx, dy = degrade(t, x, y, target_fs=120, timing_jitter=0.002,
                         drop_rate=0.02, quantize=0.0, seed=5)

    rt, rx, ry = resample_uniform(dt, dx, dy, fs=100.0)

    assert np.allclose(np.diff(rt), 0.01)
    truth_x = np.interp(rt, t, x)
    truth_y = np.interp(rt, t, y)
    assert np.max(np.abs(rx - truth_x)) < 5.0
    assert np.max(np.abs(ry - truth_y)) < 5.0


def test_resample_rejects_unsorted_time():
    t = np.array([0.0, 0.1, 0.05, 0.2])
    with pytest.raises(ValueError):
        resample_uniform(t, t, t)


def test_low_pass_keeps_slow_and_removes_fast():
    fs = 100.0
    t = np.arange(0, 10, 1 / fs)
    slow = np.sin(2 * np.pi * 1.0 * t)
    fast = np.sin(2 * np.pi * 40.0 * t)

    _, out, _ = low_pass(t, slow + fast, np.zeros_like(t), fs=fs, cutoff=15.0)

    assert np.max(np.abs(out[50:-50] - slow[50:-50])) < 0.05


def test_preprocess_trace_end_to_end():
    t, x, y = create_spiral_synth()
    dt, dx, dy = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=1)

    pt, px, py = preprocess_trace(dt, dx, dy, fs=100.0)

    assert np.allclose(np.diff(pt), 0.01)
    assert not np.any(np.isnan(px)) and not np.any(np.isnan(py))
    assert np.sqrt(np.mean(px**2 + py**2)) == pytest.approx(1.0, rel=0.05)