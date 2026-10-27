# TEST_DATASETS.PY CHECKS READING THE UCI SPIRAL DRAWING FILES ON MADE UP FILES
# RUN IT WITH python -m pytest FROM training/

import numpy as np
import pytest

from neurotrace.datasets import (
    parse_uci,
    load_uci,
    iter_uci,
    estimate_fs,
    UCI_COLUMNS,
    UCI_TESTS,
)


# Write a made up UCI file with n rows for each test id, each row dt_ms later than the last
def write_uci(path, n=50, test_ids=(0, 1), dt_ms=7):

    # Build one line of seven numbers split by semicolons for each row
    lines = []
    stamp = 1000000
    for tid in test_ids:
        for i in range(n):
            lines.append(f"{200 + i};{300 - i};0;{500 + i};900;{stamp};{tid}")
            stamp += dt_ms

    # Save the lines to the file
    path.write_text("\n".join(lines) + "\n")


# Make a made up UCI folder with 1 control file, 2 parkinson files and a readme
def make_tree(tmp_path, **kw):

    # Make each group's folder and write its files
    root = tmp_path / "uci"
    for group, names in (("control", ["C_0001"]), ("parkinson", ["P_0001", "P_0002"])):
        d = root / "hw_dataset" / group
        d.mkdir(parents=True)
        for name in names:
            write_uci(d / f"{name}.txt", **kw)

    # Add a readme file
    (root / "readme.txt").write_text("ignore me")
    return root


# READING FILES

# Check that parse_uci gives back every column with every row
def test_parse_uci_gives_every_column(tmp_path):

    # Write and read a file with 10 rows
    p = tmp_path / "one.txt"
    write_uci(p, n=10, test_ids=(0,))
    rec = parse_uci(p)

    # Check the column names and that each column has 10 values
    assert set(rec) == set(UCI_COLUMNS)
    assert all(len(v) == 10 for v in rec.values())


# Check that load_uci keeps only the rows for the test asked for
def test_load_uci_keeps_only_the_requested_test(tmp_path):
    root = make_tree(tmp_path)
    p = root / "hw_dataset" / "control" / "C_0001.txt"

    # Check each test has 50 rows and the right test name
    for test_id in (0, 1):
        rec = load_uci(p, test_id=test_id)
        assert len(rec["t"]) == 50
        assert rec["test"] == UCI_TESTS[test_id]


# Check that the time for a test starts at 0 and is in seconds
def test_load_uci_time_starts_at_zero_in_seconds(tmp_path):

    # Make files with 100 rows for each of tests 0 and 1, 7 ms apart
    root = make_tree(tmp_path, n=100, test_ids=(0, 1), dt_ms=7)

    # Load test 1, whose rows come after test 0's rows in the file
    rec = load_uci(root / "hw_dataset" / "control" / "C_0001.txt", test_id=1)

    # Check that its time starts at 0 and ends at 99 times 0.007 seconds
    assert rec["t"][0] == 0.0
    assert rec["t"][-1] == pytest.approx(99 * 0.007)


# Check that load_uci gives back None when the file has no rows for the test
def test_load_uci_returns_none_when_the_test_is_missing(tmp_path):
    p = tmp_path / "only_zero.txt"
    write_uci(p, test_ids=(0,))

    assert load_uci(p, test_id=2) is None


# LABELS AND IDS

# Check that the label comes from the control or parkinson folder name
def test_label_comes_from_the_folder_not_the_filename(tmp_path):
    root = make_tree(tmp_path)

    assert load_uci(root / "hw_dataset" / "control" / "C_0001.txt")["label"] == 0
    assert load_uci(root / "hw_dataset" / "parkinson" / "P_0001.txt")["label"] == 1


# Check that the subject id has the dataset name, the release folder and the file name
def test_subject_ids_carry_the_release(tmp_path):
    root = make_tree(tmp_path)
    rec = load_uci(root / "hw_dataset" / "control" / "C_0001.txt")

    assert rec["subject_id"] == "uci:hw_dataset:C_0001"


# Check that iter_uci reads each subject file once and skips the readme
def test_iter_uci_finds_every_subject_once_and_skips_the_readme(tmp_path):
    root = make_tree(tmp_path)
    recs = list(iter_uci(root))

    # Check that there are 3 records from 3 people, 1 control and 2 parkinson
    assert len(recs) == 3
    assert len({r["subject_id"] for r in recs}) == 3
    assert sorted(r["label"] for r in recs) == [0, 1, 1]


# SAMPLE RATE

# Check that estimate_fs gives the rate from the median gap between times when there is one long pause
def test_estimate_fs_uses_the_median_so_a_pause_does_not_count(tmp_path):

    # Make 100 times 7 ms apart with one 3 second pause in the middle
    t = np.arange(100) * 0.007
    t[50:] += 3.0

    # Check that it gives 1 over 0.007 points per second
    assert estimate_fs(t) == pytest.approx(1 / 0.007, rel=1e-6)


# Check that the sample rate is worked out from each file's own times
def test_fs_is_read_per_file_never_hardcoded(tmp_path):

    # Write one file with rows 9 ms apart and one with rows 7 ms apart
    slow = tmp_path / "slow.txt"
    fast = tmp_path / "fast.txt"
    write_uci(slow, test_ids=(0,), dt_ms=9)
    write_uci(fast, test_ids=(0,), dt_ms=7)

    # Check that they read as about 111.1 and 142.9 points per second
    assert load_uci(slow)["fs"] == pytest.approx(111.1, abs=0.1)
    assert load_uci(fast)["fs"] == pytest.approx(142.9, abs=0.1)
