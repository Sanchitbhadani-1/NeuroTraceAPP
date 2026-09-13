import numpy as np
import pytest

from neurotrace.pahaw import parse_svc, load_svc, on_surface, iter_svc, COLUMNS

# A hand-built .svc: 5 samples, 200 Hz, the middle one pen-up.
#            y     x     t_ms   pen  az   alt  pressure
SVC = """5
      100   200   1000    1   1500  600   400
      101   202   1005    1   1500  600   410
      102   204   1010    0   1500  600     0
      103   206   1015    1   1500  600   420
      104   208   1020    1   1500  600   430
"""


def test_parse_svc_columns_and_units():
    rec = parse_svc(SVC)

    assert set(rec) == {"x", "y", "t", "pen_down", "azimuth", "altitude", "pressure"}
    assert list(rec["x"]) == [200, 202, 204, 206, 208]     # x is the SECOND column
    assert list(rec["y"]) == [100, 101, 102, 103, 104]     # y is the FIRST column
    assert rec["t"][0] == 0.0                              # rebased to zero
    assert np.allclose(np.diff(rec["t"]), 0.005)           # ms -> seconds
    assert list(rec["pen_down"]) == [True, True, False, True, True]


def test_on_surface_drops_air_samples():
    t, x, y = on_surface(parse_svc(SVC))
    assert len(t) == 4
    assert 204 not in x


def test_load_svc_reads_subject_and_task_from_filename(tmp_path):
    p = tmp_path / "00026__1_1.svc"
    p.write_text(SVC)

    rec = load_svc(p)
    assert rec["subject"] == 26
    assert rec["task_id"] == 1
    assert rec["task"] == "spiral"


def test_iter_svc_filters_by_task(tmp_path):
    for name in ("00001__1_1.svc", "00001__2_1.svc", "00002__1_1.svc"):
        (tmp_path / name).write_text(SVC)

    assert len(list(iter_svc(tmp_path))) == 3
    assert len(list(iter_svc(tmp_path, task_id=1))) == 2


def test_parse_svc_rejects_wrong_column_count():
    with pytest.raises(ValueError):
        parse_svc("1\n1 2 3\n")
