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


def write_uci(path, n=50, test_ids=(0, 1), dt_ms=7):
    lines = []
    stamp = 1000000
    for tid in test_ids:
        for i in range(n):
            lines.append(f"{200 + i};{300 - i};0;{500 + i};900;{stamp};{tid}")
            stamp += dt_ms
    path.write_text("\n".join(lines) + "\n")


def make_tree(tmp_path, **kw):
    root = tmp_path / "uci"
    for group, names in (("control", ["C_0001"]), ("parkinson", ["P_0001", "P_0002"])):
        d = root / "hw_dataset" / group
        d.mkdir(parents=True)
        for name in names:
            write_uci(d / f"{name}.txt", **kw)
    (root / "readme.txt").write_text("ignore me")
    return root


# --- parsing ---------------------------------------------------------

def test_parse_uci_gives_every_column(tmp_path):
    p = tmp_path / "one.txt"
    write_uci(p, n=10, test_ids=(0,))
    rec = parse_uci(p)

    assert set(rec) == set(UCI_COLUMNS)
    assert all(len(v) == 10 for v in rec.values())


def test_load_uci_keeps_only_the_requested_test(tmp_path):
    root = make_tree(tmp_path)
    p = root / "hw_dataset" / "control" / "C_0001.txt"

    for test_id in (0, 1):
        rec = load_uci(p, test_id=test_id)
        assert len(rec["t"]) == 50
        assert rec["test"] == UCI_TESTS[test_id]


def test_load_uci_time_starts_at_zero_in_seconds(tmp_path):
    root = make_tree(tmp_path, n=100, test_ids=(0, 1), dt_ms=7)
    # Test 1's rows sit 700 ms further down the file's clock, so a loader
    # that subtracted the FILE's first timestamp would start test 1 at 0.7 s.
    rec = load_uci(root / "hw_dataset" / "control" / "C_0001.txt", test_id=1)

    assert rec["t"][0] == 0.0
    assert rec["t"][-1] == pytest.approx(99 * 0.007)


def test_load_uci_returns_none_when_the_test_is_missing(tmp_path):
    p = tmp_path / "only_zero.txt"
    write_uci(p, test_ids=(0,))

    assert load_uci(p, test_id=2) is None


# --- labels and ids --------------------------------------------------

def test_label_comes_from_the_folder_not_the_filename(tmp_path):
    root = make_tree(tmp_path)

    assert load_uci(root / "hw_dataset" / "control" / "C_0001.txt")["label"] == 0
    assert load_uci(root / "hw_dataset" / "parkinson" / "P_0001.txt")["label"] == 1


def test_subject_ids_carry_the_release(tmp_path):
    # hw_dataset and new_dataset number their subjects separately, so a bare
    # stem would collide and GroupKFold would split one person across folds.
    root = make_tree(tmp_path)
    rec = load_uci(root / "hw_dataset" / "control" / "C_0001.txt")

    assert rec["subject_id"] == "uci:hw_dataset:C_0001"


def test_iter_uci_finds_every_subject_once_and_skips_the_readme(tmp_path):
    root = make_tree(tmp_path)
    recs = list(iter_uci(root))

    assert len(recs) == 3
    assert len({r["subject_id"] for r in recs}) == 3
    assert sorted(r["label"] for r in recs) == [0, 1, 1]


# --- sample rate -----------------------------------------------------

def test_estimate_fs_uses_the_median_so_a_pause_does_not_count(tmp_path):
    t = np.arange(100) * 0.007
    t[50:] += 3.0
    # One 3 second pause. The mean gap says 42 Hz, the median still says 143.

    assert estimate_fs(t) == pytest.approx(1 / 0.007, rel=1e-6)


def test_fs_is_read_per_file_never_hardcoded(tmp_path):
    slow = tmp_path / "slow.txt"
    fast = tmp_path / "fast.txt"
    write_uci(slow, test_ids=(0,), dt_ms=9)
    write_uci(fast, test_ids=(0,), dt_ms=7)

    assert load_uci(slow)["fs"] == pytest.approx(111.1, abs=0.1)
    assert load_uci(fast)["fs"] == pytest.approx(142.9, abs=0.1)
