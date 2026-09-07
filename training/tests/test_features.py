import numpy as np
import pytest

from neurotrace.synth import create_spiral_synth
from neurotrace.preprocess import normalize
from neurotrace.pen import reference_spiral
from neurotrace.features import (
    distance_to_reference,
    change_of_radius_direction,
    kinematics,
)


# --- spiral distance -------------------------------------------------

def test_clean_spiral_lies_on_the_reference():
    _, x, y = create_spiral_synth(tremor_amp=0.0)
    x, y = normalize(x, y)

    rx, ry = normalize(*reference_spiral())

    d = distance_to_reference(x, y, rx, ry)
    assert np.max(np.abs(d)) < 0.01


# --- radius reversals ------------------------------------------------

def test_radius_reversals_zero_on_clean_spiral():
    _, x, y = create_spiral_synth(tremor_amp=0.0)

    assert change_of_radius_direction(x, y) == 0


def test_radius_reversals_count_tremor_cycles():
    _, x, y = create_spiral_synth(tremor_hz=5, tremor_amp=8)

    n = change_of_radius_direction(x, y)
    assert 150 <= n <= 250


# --- kinematics ------------------------------------------------------

def test_kinematics_on_constant_velocity_line():
    t = np.linspace(0, 10, 1001)
    x = 5.0 * t
    y = np.zeros_like(t)

    speed, accel, jerk = kinematics(t, x, y)

    assert np.allclose(speed, 5.0)
    assert np.allclose(accel, 0.0, atol=1e-8)
    assert np.allclose(jerk, 0.0, atol=1e-6)


def test_kinematics_lengths():
    t, x, y = create_spiral_synth(duration=1, fs=100)
    speed, accel, jerk = kinematics(t, x, y)

    assert len(speed) == len(t) - 1
    assert len(accel) == len(t) - 2
    assert len(jerk)  == len(t) - 3