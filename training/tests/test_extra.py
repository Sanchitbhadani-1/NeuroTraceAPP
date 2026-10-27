# TEST_EXTRA.PY CHECKS THE PEN PRESSURE AND PEN LIFT FEATURES
# RUN IT WITH python -m pytest FROM training/

import numpy as np
import pytest

from neurotrace.extra import pressure_features, in_air_features


# Check that a steady pressure gives the right mean, no spread and no trend
def test_constant_pressure_has_no_spread_and_no_trend():

    # Measure 500 points that all have pressure 600
    t = np.linspace(0, 10, 500)
    f = pressure_features(t, np.full(500, 600.0))

    # Check the mean, the spread and the trend
    assert f["pressure_mean"] == 600.0
    assert f["pressure_cv"] == pytest.approx(0.0, abs=1e-12)
    assert f["pressure_trend"] == pytest.approx(0.0, abs=1e-9)


# Check that the pressure trend is the change from start to end divided by the mean
def test_pressure_trend_is_fraction_of_mean_lost_or_gained():

    # Make a pressure that falls from 800 to 400, with a mean of 600
    t = np.linspace(0, 10, 500)
    fading = np.linspace(800, 400, 500)

    # Check that falling gives a trend of minus 400 over 600, and rising gives plus 400 over 600
    assert pressure_features(t, fading)["pressure_trend"] == pytest.approx(-400 / 600, rel=1e-6)
    assert pressure_features(t, fading[::-1])["pressure_trend"] == pytest.approx(+400 / 600, rel=1e-6)


# Check that points with zero pressure are left out of the pressure features
def test_pressure_ignores_in_air_zeros():

    # Make a steady pressure of 600 with 50 points of zero in the middle
    t = np.linspace(0, 10, 500)
    p = np.full(500, 600.0)
    p[100:150] = 0.0
    f = pressure_features(t, p)

    # Check that the mean is still 600 with no spread
    assert f["pressure_mean"] == 600.0
    assert f["pressure_cv"] == pytest.approx(0.0, abs=1e-12)


# Check that the pressure mean is NaN when there are only 5 points
def test_pressure_nan_when_too_little_on_surface():
    assert np.isnan(pressure_features(np.arange(5.0), np.ones(5))["pressure_mean"])


# Check that a pen that never lifts has no lifts and no time in the air
def test_no_lifts_when_pen_never_leaves():

    # Measure 1001 points with the pen always down
    t = np.linspace(0, 10, 1001)
    f = in_air_features(t, np.ones(1001, dtype=bool))

    # Check the lift count, the time in the air and the average lift length
    assert f["inair_n_lifts"] == 0
    assert f["inair_time_frac"] == 0.0
    assert f["inair_mean_lift_s"] == 0.0


# Check that each pen lift is counted and its length measured
def test_lifts_are_counted_and_timed():

    # Make 1001 points 10 ms apart with the pen down
    t = np.linspace(0, 10, 1001)
    down = np.ones(1001, dtype=bool)

    # Lift the pen for 1 second
    down[100:200] = False

    # Lift the pen for 0.5 seconds
    down[500:550] = False
    f = in_air_features(t, down)

    # Check the count, the longest lift, the average lift and the share of time in the air
    assert f["inair_n_lifts"] == 2
    assert f["inair_max_lift_s"] == pytest.approx(1.0, abs=0.02)
    assert f["inair_mean_lift_s"] == pytest.approx(0.75, abs=0.02)
    assert f["inair_time_frac"] == pytest.approx(0.15, abs=0.005)


# Check that a lift that lasts until the last point still counts as a lift
def test_lift_touching_the_end_still_counts():

    # Lift the pen for the last 101 points
    t = np.linspace(0, 10, 1001)
    down = np.ones(1001, dtype=bool)
    down[900:] = False

    # Check that it counts 1 lift
    assert in_air_features(t, down)["inair_n_lifts"] == 1
