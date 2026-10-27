# TEST_PAHAW.PY CHECKS READING THE PAHAW .SVC DRAWING FILES
# RUN IT WITH python -m pytest FROM training/

import numpy as np
import pytest

from neurotrace.pahaw import parse_svc, load_svc, on_surface, iter_svc, COLUMNS

# A made up .svc file with 5 points 5 ms apart, the middle point with the pen up
# The columns are y, x, time in ms, pen down, azimuth, altitude and pressure
SVC = """5
      100   200   1000    1   1500  600   400
      101   202   1005    1   1500  600   410
      102   204   1010    0   1500  600     0
      103   206   1015    1   1500  600   420
      104   208   1020    1   1500  600   430
"""


# Check that parse_svc reads every column into the right place and the right units
def test_parse_svc_columns_and_units():

    # Read the made up file
    rec = parse_svc(SVC)

    # Check the names of the columns
    assert set(rec) == {"x", "y", "t", "pen_down", "azimuth", "altitude", "pressure"}

    # Check that x comes from the second column
    assert list(rec["x"]) == [200, 202, 204, 206, 208]

    # Check that y comes from the first column
    assert list(rec["y"]) == [100, 101, 102, 103, 104]

    # Check that time starts at 0
    assert rec["t"][0] == 0.0

    # Check that time is in seconds, 0.005 apart
    assert np.allclose(np.diff(rec["t"]), 0.005)

    # Check which points have the pen down
    assert list(rec["pen_down"]) == [True, True, False, True, True]


# Check that on_surface drops the point with the pen up
def test_on_surface_drops_air_samples():
    t, x, y = on_surface(parse_svc(SVC))
    assert len(t) == 4
    assert 204 not in x


# Check that load_svc reads the subject and task numbers from the file name
def test_load_svc_reads_subject_and_task_from_filename(tmp_path):

    # Save the made up file as subject 26, task 1
    p = tmp_path / "00026__1_1.svc"
    p.write_text(SVC)

    # Check the subject, the task number and the task name
    rec = load_svc(p)
    assert rec["subject"] == 26
    assert rec["task_id"] == 1
    assert rec["task"] == "spiral"


# Check that iter_svc reads every file, or only the files for one task
def test_iter_svc_filters_by_task(tmp_path):

    # Save 3 files, 2 of them for task 1
    for name in ("00001__1_1.svc", "00001__2_1.svc", "00002__1_1.svc"):
        (tmp_path / name).write_text(SVC)

    # Check that it finds 3 files in all and 2 for task 1
    assert len(list(iter_svc(tmp_path))) == 3
    assert len(list(iter_svc(tmp_path, task_id=1))) == 2


# Check that parse_svc raises an error for rows with the wrong number of columns
def test_parse_svc_rejects_wrong_column_count():
    with pytest.raises(ValueError):
        parse_svc("1\n1 2 3\n")
