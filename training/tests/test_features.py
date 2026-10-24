import numpy as np
import pytest

from neurotrace.synth import (
    create_spiral_synth,
    create_writing_synth,
    create_tapping_synth,
    degrade,
    FIDELITY_TIERS,
)
from neurotrace.preprocess import normalize, preprocess_trace
from neurotrace.pen import reference_spiral
from neurotrace.features import (
    spiral_fit_residual,
    major_radius_reversals,
    kinematics,
    speed_features,
    deviation_features,
    log_dimensionless_jerk,
    sparc,
    tremor_residual,
    band_power,
    dominant_frequency,
    loop_heights,
    amplitude_trend,
    extract_spiral_features,
    extract_writing_features,
    extract_tapping_features,
    features_from_trace,
)

FS = 100.0


def prepped_spiral(**kw):
    t, x, y = create_spiral_synth(**kw)
    return preprocess_trace(t, x, y, fs=FS)


def prepped_writing(**kw):
    t, x, y = create_writing_synth(**kw)
    return preprocess_trace(t, x, y, fs=FS)


# --- spiral deviation ------------------------------------------------

def test_clean_spiral_has_almost_no_deviation():
    _, x, y = create_spiral_synth(tremor_amp=0.0)
    x, y = normalize(x, y)

    assert np.std(spiral_fit_residual(x, y)) < 0.02
    # Not exactly 0: the cos/sin center correction is first order. It was
    # 0.048 with no correction at all, and that part moved with turn count.


def test_deviation_is_the_same_whatever_spiral_was_drawn():
    # THE reason this replaced distance_to_reference. A 4-turn counterclockwise
    # spiral and a 2.75-turn clockwise one are different drawings of the same
    # quality, so they must score the same. Against a saved template they did
    # not - UCI's spiral is 2.75 turns clockwise and ours is 3.76 the other
    # way, so the old feature measured the template, not the hand.
    a = []
    for turns, flip in ((4, +1), (2.75, -1), (3, +1), (2.75, +1)):
        _, x, y = create_spiral_synth(turns=turns, tremor_hz=5, tremor_amp=8)
        x, y = normalize(x, flip * y)
        a.append(deviation_features(spiral_fit_residual(x, y))["std_deviation"])

    assert max(a) / min(a) < 1.3


def test_deviation_grows_with_tremor():
    _, x, y = create_spiral_synth(tremor_amp=0.0)
    clean = deviation_features(spiral_fit_residual(*normalize(x, y)))

    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=8)
    shaky = deviation_features(spiral_fit_residual(*normalize(x, y)))

    assert shaky["std_deviation"] > 2.5 * clean["std_deviation"]


def test_deviation_refuses_a_trace_too_short_to_be_a_spiral():
    # A scribble has no angular span, so the fit would be meaningless.
    # build_features catches this and skips the row.
    _, x, y = create_spiral_synth(turns=0.3)

    with pytest.raises(ValueError):
        spiral_fit_residual(*normalize(x, y))


# --- major radius reversals ------------------------------------------

def test_no_major_reversals_on_a_clean_spiral():
    _, x, y = create_spiral_synth(tremor_amp=0.0)

    assert major_radius_reversals(*normalize(x, y)) == 0


def test_quantization_alone_creates_no_major_reversals():
    # THE reason this replaced change_of_radius_direction. Rounding a smooth
    # spiral to a coarse grid made the old feature count hundreds of flips, so
    # healthy subjects out-scored patients on UCI and the feature ran backward.
    t, x, y = create_spiral_synth(tremor_amp=0.0)

    for grid in (1, 2, 4, 8):
        qx, qy = degrade(t, x, y, quantize=grid, seed=0)[1:]
        assert major_radius_reversals(*normalize(qx, qy)) == 0


def test_major_reversals_count_real_doubling_back():
    # Tremor big enough to clear min_retrace: 5 Hz for 20 s is 100 cycles,
    # each pulling the radius in and back out, so about 200.
    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=60)

    assert 150 <= major_radius_reversals(*normalize(x, y)) <= 250


def test_small_wobble_is_ignored_on_purpose():
    # Below min_retrace nothing is counted. That is the point, not a bug:
    # it is what keeps grid noise out.
    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=2)

    assert major_radius_reversals(*normalize(x, y)) == 0


# --- kinematics ------------------------------------------------------

def test_kinematics_on_constant_velocity_line():
    t = np.linspace(0, 10, 1001)
    x = 5.0 * t
    y = np.zeros_like(t)

    speed, accel, jerk = kinematics(t, x, y)

    assert np.allclose(speed, 5.0)
    assert np.allclose(accel, 0.0, atol=1e-8)
    assert np.allclose(jerk, 0.0, atol=1e-6)


def test_kinematics_same_length_as_input():
    t, x, y = create_spiral_synth(duration=1, fs=100)
    speed, accel, jerk = kinematics(t, x, y)

    assert len(speed) == len(accel) == len(jerk) == len(t)


def test_speed_features_on_constant_velocity_line():
    t = np.linspace(0, 10, 1001)
    speed, _, _ = kinematics(t, 5.0 * t, np.zeros_like(t))
    f = speed_features(speed)

    assert f["mean_speed"] == pytest.approx(5.0)
    assert f["std_speed"] == pytest.approx(0.0, abs=1e-9)


# --- smoothness ------------------------------------------------------

def test_ldlj_is_lower_with_tremor():
    t, x, y = prepped_spiral(tremor_amp=0.0)
    s, _, j = kinematics(t, x, y)
    clean = log_dimensionless_jerk(t, s, j)

    t, x, y = prepped_spiral(tremor_hz=5, tremor_amp=8)
    s, _, j = kinematics(t, x, y)
    shaky = log_dimensionless_jerk(t, s, j)

    assert shaky < clean


def test_sparc_is_lower_with_tremor():
    t, x, y = prepped_spiral(tremor_amp=0.0)
    clean = sparc(kinematics(t, x, y)[0], FS)

    t, x, y = prepped_spiral(tremor_hz=5, tremor_amp=8)
    shaky = sparc(kinematics(t, x, y)[0], FS)

    assert np.isfinite(clean) and np.isfinite(shaky)
    assert shaky < clean


# --- tremor ----------------------------------------------------------

def test_tremor_frequency_is_recovered():
    t, x, y = prepped_spiral(tremor_hz=5.5, tremor_amp=8)
    residual = tremor_residual(x, y, FS)

    assert dominant_frequency(residual, FS) == pytest.approx(5.5, abs=0.3)


def test_tremor_lands_in_the_right_band():
    t, x, y = prepped_spiral(tremor_hz=5.0, tremor_amp=8)
    r = tremor_residual(x, y, FS)
    assert band_power(r, FS, (4, 6)) > 10 * band_power(r, FS, (6, 12))

    t, x, y = prepped_spiral(tremor_hz=9.0, tremor_amp=8)
    r = tremor_residual(x, y, FS)
    assert band_power(r, FS, (6, 12)) > 10 * band_power(r, FS, (4, 6))


def test_clean_spiral_has_no_tremor_power():
    t, x, y = prepped_spiral(tremor_amp=0.0)
    r = tremor_residual(x, y, FS)

    t2, x2, y2 = prepped_spiral(tremor_hz=5.5, tremor_amp=8)
    r2 = tremor_residual(x2, y2, FS)

    assert band_power(r, FS, (4, 6)) < 1e-6 * band_power(r2, FS, (4, 6))


def test_tremor_frequency_survives_phone_tier_degradation():
    # The whole reason resample_uniform exists: wreck the sampling, repair
    # it, and the frequency measurement is still right.
    t, x, y = create_spiral_synth(tremor_hz=5.5, tremor_amp=8)
    dt, dx, dy = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=3)
    pt, px, py = preprocess_trace(dt, dx, dy, fs=FS)

    residual = tremor_residual(px, py, FS)
    assert dominant_frequency(residual, FS) == pytest.approx(5.5, abs=0.3)


# --- writing ---------------------------------------------------------

def test_loop_heights_finds_every_letter():
    t, x, y = prepped_writing(size_trend=-0.05)
    assert len(loop_heights(y)) == 5

    t, x, y = prepped_writing(size_trend=-0.05, tremor_hz=5, tremor_amp=8)
    assert len(loop_heights(y)) == 5


def test_amplitude_trend_recovers_size_trend_with_sign():
    for size_trend in (-0.10, -0.05, 0.0, +0.05):
        t, x, y = prepped_writing(size_trend=size_trend)
        recovered = amplitude_trend(loop_heights(y))
        assert recovered == pytest.approx(size_trend, abs=0.005)


def test_amplitude_trend_sign_is_preserved():
    # PD shrinks, ET grows. abs() anywhere in this path makes them identical.
    t, x, y = prepped_writing(size_trend=-0.05)
    pd = amplitude_trend(loop_heights(y))

    t, x, y = prepped_writing(size_trend=+0.05)
    et = amplitude_trend(loop_heights(y))

    assert pd < 0.0 < et


def test_amplitude_trend_survives_tremor():
    t, x, y = prepped_writing(size_trend=-0.05, tremor_hz=5, tremor_amp=8)
    assert amplitude_trend(loop_heights(y)) == pytest.approx(-0.05, abs=0.01)


# --- tapping ---------------------------------------------------------

def test_tapping_default_is_perfectly_regular():
    f = extract_tapping_features(*create_tapping_synth())

    assert f["tap_count"] == 60
    assert f["tap_rate"] == pytest.approx(4.0, rel=0.01)
    assert f["tap_rhythm_sd"] == pytest.approx(0.0, abs=1e-9)
    assert f["tap_rate_trend"] == pytest.approx(0.0, abs=1e-6)
    assert f["tap_amplitude_trend"] == pytest.approx(0.0, abs=1e-6)


def test_tapping_recovers_rate_trend_with_sign():
    f = extract_tapping_features(*create_tapping_synth(rate_trend=-0.01))
    assert f["tap_rate_trend"] == pytest.approx(-0.01, abs=0.001)

    f = extract_tapping_features(*create_tapping_synth(rate_trend=+0.01))
    assert f["tap_rate_trend"] == pytest.approx(+0.01, abs=0.001)


def test_tapping_recovers_amplitude_trend_with_sign():
    f = extract_tapping_features(*create_tapping_synth(amp_trend=-0.01))
    assert f["tap_amplitude_trend"] == pytest.approx(-0.01, abs=0.001)

    f = extract_tapping_features(*create_tapping_synth(amp_trend=+0.02))
    assert f["tap_amplitude_trend"] == pytest.approx(+0.02, abs=0.001)


def test_tapping_rhythm_sd_matches_injected_jitter():
    f = extract_tapping_features(*create_tapping_synth(jitter=0.02, seed=1))
    assert f["tap_rhythm_sd"] == pytest.approx(0.02, rel=0.25)


# --- assembly --------------------------------------------------------

SPIRAL_ORDER = [
    "spiral_duration",
    "spiral_max_deviation", "spiral_mean_deviation", "spiral_std_deviation",
    "spiral_major_reversals",
    "spiral_mean_speed", "spiral_std_speed",
    "spiral_ldlj", "spiral_sparc",
    "spiral_tremor_4_6", "spiral_tremor_6_12", "spiral_tremor_dominant_hz",
]


def test_extract_spiral_features_order_and_finite():
    t, x, y = prepped_spiral(tremor_hz=5, tremor_amp=60)
    f = extract_spiral_features(t, x, y, fs=FS)

    assert list(f.keys()) == SPIRAL_ORDER
    assert all(np.isfinite(v) for v in f.values())
    assert f["spiral_major_reversals"] > 100


def test_extract_writing_features_finite_with_sign():
    t, x, y = prepped_writing(size_trend=-0.05)
    f = extract_writing_features(t, x, y, fs=FS)

    assert list(f.keys())[:3] == ["writing_duration", "writing_n_loops", "writing_amplitude_trend"]
    assert all(np.isfinite(v) for v in f.values())
    assert f["writing_amplitude_trend"] < 0


def test_features_from_trace_dispatches_on_task():
    t, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=60)
    trace = {
        "task": "spiral", "hand": "right", "inputType": "pencil",
        "deviceLabel": "test",
        "samples": [{"t": float(a), "x": float(b), "y": float(c)} for a, b, c in zip(t, x, y)],
    }
    f = features_from_trace(trace, fs=FS)
    assert list(f.keys()) == SPIRAL_ORDER

    tap_t, tap_x, tap_y = create_tapping_synth(rate_trend=-0.01)
    trace = {
        "task": "tap", "hand": "right", "inputType": "touch",
        "deviceLabel": "test",
        "samples": [{"t": float(a), "x": float(b), "y": float(c)} for a, b, c in zip(tap_t, tap_x, tap_y)],
    }
    f = features_from_trace(trace)
    assert f["tap_rate_trend"] == pytest.approx(-0.01, abs=0.001)

    with pytest.raises(ValueError):
        features_from_trace({"task": "motion", "samples": trace["samples"]})
