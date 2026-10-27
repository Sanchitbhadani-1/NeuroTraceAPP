# TEST_FEATURES.PY CHECKS THE FEATURE FUNCTIONS ON MADE UP DRAWINGS
# RUN IT WITH python -m pytest FROM training/

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

# The number of points per second used in these tests
FS = 100.0


# Make a made up spiral and run it through every cleanup step
def prepped_spiral(**kw):
    t, x, y = create_spiral_synth(**kw)
    return preprocess_trace(t, x, y, fs=FS)


# Make made up writing and run it through every cleanup step
def prepped_writing(**kw):
    t, x, y = create_writing_synth(**kw)
    return preprocess_trace(t, x, y, fs=FS)


# SPIRAL DEVIATION

# Check that a spiral with no tremor is almost exactly on its fitted spiral
def test_clean_spiral_has_almost_no_deviation():
    _, x, y = create_spiral_synth(tremor_amp=0.0)
    x, y = normalize(x, y)

    assert np.std(spiral_fit_residual(x, y)) < 0.02


# Check that the deviation is about the same for spirals with different turns and directions
def test_deviation_is_the_same_whatever_spiral_was_drawn():

    # Measure the deviation of four spirals with the same tremor, flipping some upside down
    a = []
    for turns, flip in ((4, +1), (2.75, -1), (3, +1), (2.75, +1)):
        _, x, y = create_spiral_synth(turns=turns, tremor_hz=5, tremor_amp=8)
        x, y = normalize(x, flip * y)
        a.append(deviation_features(spiral_fit_residual(x, y))["std_deviation"])

    # Check that the largest is less than 1.3 times the smallest
    assert max(a) / min(a) < 1.3


# Check that a spiral with tremor has more than 2.5 times the deviation of one without
def test_deviation_grows_with_tremor():

    # Measure a spiral with no tremor
    _, x, y = create_spiral_synth(tremor_amp=0.0)
    clean = deviation_features(spiral_fit_residual(*normalize(x, y)))

    # Measure a spiral with a 5 Hz tremor
    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=8)
    shaky = deviation_features(spiral_fit_residual(*normalize(x, y)))

    assert shaky["std_deviation"] > 2.5 * clean["std_deviation"]


# Check that spiral_fit_residual raises an error for a spiral of only 0.3 turns
def test_deviation_refuses_a_trace_too_short_to_be_a_spiral():
    _, x, y = create_spiral_synth(turns=0.3)

    with pytest.raises(ValueError):
        spiral_fit_residual(*normalize(x, y))


# MAJOR RADIUS REVERSALS

# Check that a spiral with no tremor has no major reversals
def test_no_major_reversals_on_a_clean_spiral():
    _, x, y = create_spiral_synth(tremor_amp=0.0)

    assert major_radius_reversals(*normalize(x, y)) == 0


# Check that rounding a smooth spiral to a grid of 1, 2, 4 or 8 gives no major reversals
def test_quantization_alone_creates_no_major_reversals():
    t, x, y = create_spiral_synth(tremor_amp=0.0)

    # Round the spiral to each grid size and count the major reversals
    for grid in (1, 2, 4, 8):
        qx, qy = degrade(t, x, y, quantize=grid, seed=0)[1:]
        assert major_radius_reversals(*normalize(qx, qy)) == 0


# Check that a large 5 Hz tremor gives between 150 and 250 major reversals
def test_major_reversals_count_real_doubling_back():
    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=60)

    assert 150 <= major_radius_reversals(*normalize(x, y)) <= 250


# Check that a small 5 Hz tremor gives no major reversals
def test_small_wobble_is_ignored_on_purpose():
    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=2)

    assert major_radius_reversals(*normalize(x, y)) == 0


# KINEMATICS

# Check that a straight line at a steady speed of 5 has no acceleration and no jerk
def test_kinematics_on_constant_velocity_line():

    # Make a line along x moving 5 per second for 10 seconds
    t = np.linspace(0, 10, 1001)
    x = 5.0 * t
    y = np.zeros_like(t)

    speed, accel, jerk = kinematics(t, x, y)

    # Check the speed, acceleration and jerk
    assert np.allclose(speed, 5.0)
    assert np.allclose(accel, 0.0, atol=1e-8)
    assert np.allclose(jerk, 0.0, atol=1e-6)


# Check that speed, acceleration and jerk have one value for every point
def test_kinematics_same_length_as_input():
    t, x, y = create_spiral_synth(duration=1, fs=100)
    speed, accel, jerk = kinematics(t, x, y)

    assert len(speed) == len(accel) == len(jerk) == len(t)


# Check that a steady speed of 5 gives a mean speed of 5 and no spread
def test_speed_features_on_constant_velocity_line():
    t = np.linspace(0, 10, 1001)
    speed, _, _ = kinematics(t, 5.0 * t, np.zeros_like(t))
    f = speed_features(speed)

    assert f["mean_speed"] == pytest.approx(5.0)
    assert f["std_speed"] == pytest.approx(0.0, abs=1e-9)


# SMOOTHNESS

# Check that the log dimensionless jerk is lower for a spiral with tremor
def test_ldlj_is_lower_with_tremor():

    # Measure a spiral with no tremor
    t, x, y = prepped_spiral(tremor_amp=0.0)
    s, _, j = kinematics(t, x, y)
    clean = log_dimensionless_jerk(t, s, j)

    # Measure a spiral with a 5 Hz tremor
    t, x, y = prepped_spiral(tremor_hz=5, tremor_amp=8)
    s, _, j = kinematics(t, x, y)
    shaky = log_dimensionless_jerk(t, s, j)

    assert shaky < clean


# Check that sparc gives real numbers and is lower for a spiral with tremor
def test_sparc_is_lower_with_tremor():

    # Measure a spiral with no tremor
    t, x, y = prepped_spiral(tremor_amp=0.0)
    clean = sparc(kinematics(t, x, y)[0], FS)

    # Measure a spiral with a 5 Hz tremor
    t, x, y = prepped_spiral(tremor_hz=5, tremor_amp=8)
    shaky = sparc(kinematics(t, x, y)[0], FS)

    assert np.isfinite(clean) and np.isfinite(shaky)
    assert shaky < clean


# TREMOR

# Check that dominant_frequency finds a 5.5 Hz tremor
def test_tremor_frequency_is_recovered():
    t, x, y = prepped_spiral(tremor_hz=5.5, tremor_amp=8)
    residual = tremor_residual(x, y, FS)

    assert dominant_frequency(residual, FS) == pytest.approx(5.5, abs=0.3)


# Check that a 5 Hz tremor shows up in the 4 to 6 band and a 9 Hz tremor in the 6 to 12 band
def test_tremor_lands_in_the_right_band():

    # Check that a 5 Hz tremor has over 10 times more power in 4 to 6 than in 6 to 12
    t, x, y = prepped_spiral(tremor_hz=5.0, tremor_amp=8)
    r = tremor_residual(x, y, FS)
    assert band_power(r, FS, (4, 6)) > 10 * band_power(r, FS, (6, 12))

    # Check that a 9 Hz tremor has over 10 times more power in 6 to 12 than in 4 to 6
    t, x, y = prepped_spiral(tremor_hz=9.0, tremor_amp=8)
    r = tremor_residual(x, y, FS)
    assert band_power(r, FS, (6, 12)) > 10 * band_power(r, FS, (4, 6))


# Check that a spiral with no tremor has almost no power in the 4 to 6 band
def test_clean_spiral_has_no_tremor_power():

    # Measure a spiral with no tremor
    t, x, y = prepped_spiral(tremor_amp=0.0)
    r = tremor_residual(x, y, FS)

    # Measure a spiral with a 5.5 Hz tremor
    t2, x2, y2 = prepped_spiral(tremor_hz=5.5, tremor_amp=8)
    r2 = tremor_residual(x2, y2, FS)

    # Check that the first has less than a millionth of the second's power
    assert band_power(r, FS, (4, 6)) < 1e-6 * band_power(r2, FS, (4, 6))


# Check that the tremor frequency is still found after the drawing is made phone quality and cleaned up
def test_tremor_frequency_survives_phone_tier_degradation():

    # Make a spiral with a 5.5 Hz tremor, make it phone quality, then clean it up
    t, x, y = create_spiral_synth(tremor_hz=5.5, tremor_amp=8)
    dt, dx, dy = degrade(t, x, y, **FIDELITY_TIERS["phone"], seed=3)
    pt, px, py = preprocess_trace(dt, dx, dy, fs=FS)

    # Check that the tremor frequency is still about 5.5 Hz
    residual = tremor_residual(px, py, FS)
    assert dominant_frequency(residual, FS) == pytest.approx(5.5, abs=0.3)


# WRITING

# Check that loop_heights finds all 5 letters, with and without tremor
def test_loop_heights_finds_every_letter():
    t, x, y = prepped_writing(size_trend=-0.05)
    assert len(loop_heights(y)) == 5

    t, x, y = prepped_writing(size_trend=-0.05, tremor_hz=5, tremor_amp=8)
    assert len(loop_heights(y)) == 5


# Check that amplitude_trend gives back each size trend the writing was made with
def test_amplitude_trend_recovers_size_trend_with_sign():
    for size_trend in (-0.10, -0.05, 0.0, +0.05):
        t, x, y = prepped_writing(size_trend=size_trend)
        recovered = amplitude_trend(loop_heights(y))
        assert recovered == pytest.approx(size_trend, abs=0.005)


# Check that shrinking writing gives a minus trend and growing writing gives a plus trend
def test_amplitude_trend_sign_is_preserved():

    # Measure writing that shrinks
    t, x, y = prepped_writing(size_trend=-0.05)
    pd = amplitude_trend(loop_heights(y))

    # Measure writing that grows
    t, x, y = prepped_writing(size_trend=+0.05)
    et = amplitude_trend(loop_heights(y))

    assert pd < 0.0 < et


# Check that amplitude_trend still finds the size trend in writing with tremor
def test_amplitude_trend_survives_tremor():
    t, x, y = prepped_writing(size_trend=-0.05, tremor_hz=5, tremor_amp=8)
    assert amplitude_trend(loop_heights(y)) == pytest.approx(-0.05, abs=0.01)


# TAPPING

# Check the tapping features for the default taps, 60 taps at 4 per second with no changes
def test_tapping_default_is_perfectly_regular():
    f = extract_tapping_features(*create_tapping_synth())

    assert f["tap_count"] == 60
    assert f["tap_rate"] == pytest.approx(4.0, rel=0.01)
    assert f["tap_rhythm_sd"] == pytest.approx(0.0, abs=1e-9)
    assert f["tap_rate_trend"] == pytest.approx(0.0, abs=1e-6)
    assert f["tap_amplitude_trend"] == pytest.approx(0.0, abs=1e-6)


# Check that the tap rate trend comes back with the same value and sign it was made with
def test_tapping_recovers_rate_trend_with_sign():
    f = extract_tapping_features(*create_tapping_synth(rate_trend=-0.01))
    assert f["tap_rate_trend"] == pytest.approx(-0.01, abs=0.001)

    f = extract_tapping_features(*create_tapping_synth(rate_trend=+0.01))
    assert f["tap_rate_trend"] == pytest.approx(+0.01, abs=0.001)


# Check that the tap amplitude trend comes back with the same value and sign it was made with
def test_tapping_recovers_amplitude_trend_with_sign():
    f = extract_tapping_features(*create_tapping_synth(amp_trend=-0.01))
    assert f["tap_amplitude_trend"] == pytest.approx(-0.01, abs=0.001)

    f = extract_tapping_features(*create_tapping_synth(amp_trend=+0.02))
    assert f["tap_amplitude_trend"] == pytest.approx(+0.02, abs=0.001)


# Check that the tap rhythm spread is close to the jitter the taps were made with
def test_tapping_rhythm_sd_matches_injected_jitter():
    f = extract_tapping_features(*create_tapping_synth(jitter=0.02, seed=1))
    assert f["tap_rhythm_sd"] == pytest.approx(0.02, rel=0.25)


# PUTTING THE FEATURES TOGETHER

# The spiral feature names in the order they should come back
SPIRAL_ORDER = [
    "spiral_duration",
    "spiral_max_deviation", "spiral_mean_deviation", "spiral_std_deviation",
    "spiral_major_reversals",
    "spiral_mean_speed", "spiral_std_speed",
    "spiral_ldlj", "spiral_sparc",
    "spiral_tremor_4_6", "spiral_tremor_6_12", "spiral_tremor_dominant_hz",
]


# Check that the spiral features come back in order, as real numbers
def test_extract_spiral_features_order_and_finite():
    t, x, y = prepped_spiral(tremor_hz=5, tremor_amp=60)
    f = extract_spiral_features(t, x, y, fs=FS)

    assert list(f.keys()) == SPIRAL_ORDER
    assert all(np.isfinite(v) for v in f.values())
    assert f["spiral_major_reversals"] > 100


# Check that the writing features start with the right names, are real numbers, and keep a minus trend
def test_extract_writing_features_finite_with_sign():
    t, x, y = prepped_writing(size_trend=-0.05)
    f = extract_writing_features(t, x, y, fs=FS)

    assert list(f.keys())[:3] == ["writing_duration", "writing_n_loops", "writing_amplitude_trend"]
    assert all(np.isfinite(v) for v in f.values())
    assert f["writing_amplitude_trend"] < 0


# Check that features_from_trace picks the right features for each task
def test_features_from_trace_dispatches_on_task():

    # Check that a spiral trace gives the spiral features
    t, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=60)
    trace = {
        "task": "spiral", "hand": "right", "inputType": "pencil",
        "deviceLabel": "test",
        "samples": [{"t": float(a), "x": float(b), "y": float(c)} for a, b, c in zip(t, x, y)],
    }
    f = features_from_trace(trace, fs=FS)
    assert list(f.keys()) == SPIRAL_ORDER

    # Check that a tap trace gives the tapping features
    tap_t, tap_x, tap_y = create_tapping_synth(rate_trend=-0.01)
    trace = {
        "task": "tap", "hand": "right", "inputType": "touch",
        "deviceLabel": "test",
        "samples": [{"t": float(a), "x": float(b), "y": float(c)} for a, b, c in zip(tap_t, tap_x, tap_y)],
    }
    f = features_from_trace(trace)
    assert f["tap_rate_trend"] == pytest.approx(-0.01, abs=0.001)

    # Check that an unknown task raises an error
    with pytest.raises(ValueError):
        features_from_trace({"task": "motion", "samples": trace["samples"]})
