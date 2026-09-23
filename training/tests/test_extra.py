import numpy as np
import pytest

from neurotrace.extra import pressure_features, in_air_features


def test_constant_pressure_has_no_spread_and_no_trend():
    t = np.linspace(0, 10, 500)
    f = pressure_features(t, np.full(500, 600.0))

    assert f["pressure_mean"] == 600.0
    assert f["pressure_cv"] == pytest.approx(0.0, abs=1e-12)
    assert f["pressure_trend"] == pytest.approx(0.0, abs=1e-9)


def test_pressure_trend_is_fraction_of_mean_lost_or_gained():
    t = np.linspace(0, 10, 500)
    fading = np.linspace(800, 400, 500)
    # Ends at half of where it started; mean is 600, drop is 400 -> -0.667

    assert pressure_features(t, fading)["pressure_trend"] == pytest.approx(-400 / 600, rel=1e-6)
    assert pressure_features(t, fading[::-1])["pressure_trend"] == pytest.approx(+400 / 600, rel=1e-6)


def test_pressure_ignores_in_air_zeros():
    t = np.linspace(0, 10, 500)
    p = np.full(500, 600.0)
    p[100:150] = 0.0
    f = pressure_features(t, p)

    assert f["pressure_mean"] == 600.0
    assert f["pressure_cv"] == pytest.approx(0.0, abs=1e-12)


def test_pressure_nan_when_too_little_on_surface():
    assert np.isnan(pressure_features(np.arange(5.0), np.ones(5))["pressure_mean"])


def test_no_lifts_when_pen_never_leaves():
    t = np.linspace(0, 10, 1001)
    f = in_air_features(t, np.ones(1001, dtype=bool))

    assert f["inair_n_lifts"] == 0
    assert f["inair_time_frac"] == 0.0
    assert f["inair_mean_lift_s"] == 0.0


def test_lifts_are_counted_and_timed():
    t = np.linspace(0, 10, 1001)              # 10 ms per sample
    down = np.ones(1001, dtype=bool)
    down[100:200] = False                     # 1.0 s lift
    down[500:550] = False                     # 0.5 s lift
    f = in_air_features(t, down)

    assert f["inair_n_lifts"] == 2
    assert f["inair_max_lift_s"] == pytest.approx(1.0, abs=0.02)
    assert f["inair_mean_lift_s"] == pytest.approx(0.75, abs=0.02)
    assert f["inair_time_frac"] == pytest.approx(0.15, abs=0.005)


def test_lift_touching_the_end_still_counts():
    t = np.linspace(0, 10, 1001)
    down = np.ones(1001, dtype=bool)
    down[900:] = False

    assert in_air_features(t, down)["inair_n_lifts"] == 1
