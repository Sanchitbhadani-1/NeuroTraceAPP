import json

import numpy as np
import pytest

from neurotrace.collected import age_bracket, iter_collected, parse_session


def session(subject="a1", diagnosis="none", age=72, n_trials=3, n=200):
    t = np.linspace(0, 8, n)
    return {
        "subjectId": subject, "diagnosis": diagnosis, "age": age,
        "hand": "right", "session": 1, "deviceLabel": "iPad Pro 11",
        "trials": [{
            "trial": i + 1, "task": "spiral", "inputType": "pencil",
            "samples": [{"t": float(a), "x": float(a), "y": 0.0, "pressure": 0.5}
                        for a in t],
        } for i in range(n_trials)],
    }


def test_age_brackets_split_where_we_say_they_do():
    assert age_bracket(55) == "50s"
    assert age_bracket(59) == "50s"
    assert age_bracket(60) == "60s"
    assert age_bracket(79) == "70s"
    assert age_bracket(80) == "80+"
    assert age_bracket(None) is None


def test_one_record_per_trial():
    recs = list(parse_session(session(n_trials=3)))

    assert len(recs) == 3
    assert [r["trial"] for r in recs] == [1, 2, 3]
    assert all(r["subject_id"] == "nt:a1" for r in recs)


def test_diagnosis_is_kept_separately_from_label():
    # Essential tremor is not Parkinson's, but it is not healthy either.
    # label says 0; the healthy reference filters on diagnosis, not label.
    rec = next(parse_session(session(diagnosis="essential_tremor")))

    assert rec["label"] == 0
    assert rec["diagnosis"] == "essential_tremor"


def test_parkinsons_is_labeled():
    assert next(parse_session(session(diagnosis="parkinsons")))["label"] == 1


def test_reads_a_file_of_many_sessions(tmp_path):
    p = tmp_path / "visit.json"
    p.write_text(json.dumps([session("a1"), session("a2"), session("a3")]))

    recs = list(iter_collected(tmp_path))
    assert len(recs) == 9
    assert len({r["subject_id"] for r in recs}) == 3


def test_skips_other_tasks(tmp_path):
    s = session()
    s["trials"][0]["task"] = "writing"
    (tmp_path / "s.json").write_text(json.dumps(s))

    assert len(list(iter_collected(tmp_path, task="spiral"))) == 2
    assert len(list(iter_collected(tmp_path, task="writing"))) == 1


def test_missing_pressure_reads_zero_not_crash():
    s = session()
    for tr in s["trials"]:
        for smp in tr["samples"]:
            del smp["pressure"]

    assert np.all(next(parse_session(s))["pressure"] == 0.0)
