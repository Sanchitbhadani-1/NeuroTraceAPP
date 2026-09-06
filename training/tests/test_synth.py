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



def peak_ratio(y):
    peaks, _ = find_peaks(y)
    assert len(peaks) == 5, f"expected 5 loops, found {len(peaks)}"
    return y[peaks[-1]] / y[peaks[0]]



def radius(x, y):
    return np.sqrt(x**2 + y**2)


#---------------------SPIRAL TESTS-----------------------------

def test_spiral_shape_and_time_axis():
    t, x, y = create_spiral_synth(duration=10, fs=100)

    assert len(t) == len(x) == len(y) == 1000
    assert t[0] == pytest.approx(0.0)
    assert t[-1] == pytest.approx(10.0)



def test_spiral_radius_monotonic_only_without_tremor():
    _, x, y = create_spiral_synth()
    assert np.all(np.diff(radius(x, y)) > 0)

    _, xt, yt = create_spiral_synth(tremor_hz=5, tremor_amp=8)
    assert not np.all(np.diff(radius(xt, yt)) > 0)



#------------------WRITING TESTS------------------------

def test_size_trend_effect():
    _, _, shrinking = create_writing_synth(size_trend=-0.5)
    _, _, growing = create_writing_synth(size_trend=0.5)
    assert peak_ratio(shrinking) < 1.0
    assert peak_ratio(growing) > 1.0



def test_writing_envelope_magnitudes():
    _, _, flat = create_writing_synth(size_trend=0.0)
    _, _, pd   = create_writing_synth(size_trend=-0.05)
    _, _, et   = create_writing_synth(size_trend=+0.05)

    assert peak_ratio(flat) == pytest.approx(1.0,    rel=0.01)
    assert peak_ratio(pd)   == pytest.approx(0.8145, rel=0.01)
    assert peak_ratio(et)   == pytest.approx(1.2155, rel=0.01)



def test_writing_trend_sign_is_preserved():
    """
    The magnitude says a sequence effect exists. The SIGN says which
    disease: PD shrinks, ET grows. If anything downstream ever wraps
    this quantity in abs(), the two become indistinguishable — and
    this test is what catches it.
    """
    _, _, pd = create_writing_synth(size_trend=-0.05)
    _, _, et = create_writing_synth(size_trend=+0.05)

    assert peak_ratio(pd) < 1.0
    assert peak_ratio(et) > 1.0



#-------------TAPPING TESTS------------------------------
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



def test_tapping_slows_down():
    tap_t, _, _ = create_tapping_synth(rate_trend=-0.01)
    gaps = np.diff(tap_t)

    assert gaps[-1] / gaps[0] == pytest.approx(1.791, rel=0.01)



def test_tapping_amplitude_shrinks():
    _, tap_x, _ = create_tapping_synth(amp_trend=-0.01)

    assert abs(tap_x[-1]) / abs(tap_x[0]) == pytest.approx(0.553, rel=0.01)


def test_tapping_alternates_sides():
    _, tap_x, _ = create_tapping_synth()

    assert np.all(np.sign(tap_x[:-1]) != np.sign(tap_x[1:]))



#--------------------OTHER TESTS--------------------
def test_degrade_breaks_uniform_sampling():
    t, x, y = create_spiral_synth()
    assert np.std(np.diff(t)) == pytest.approx(0.0, abs=1e-12)

    dt, dx, dy = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=3)

    assert np.std(np.diff(dt)) > 0.001      # gaps are now irregular
    assert len(dt) < len(t)                 # samples were lost
    assert np.all(np.diff(dt) > 0)          # time still moves forward