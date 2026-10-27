# TEST_COLLECTED.PY CHECKS READING THE DRAWING SESSIONS SAVED BY THE APP
# RUN IT WITH python -m pytest FROM training/

import json

import numpy as np
import pytest

from neurotrace.collected import age_bracket, iter_collected, parse_session


# Make a made up session with n_trials spiral trials of n points each
def session(subject="a1", diagnosis="none", age=72, n_trials=3, n=200):

    # Make n evenly spaced times from 0 to 8 seconds
    t = np.linspace(0, 8, n)

    # Build the session with the person's details and the trials, each point moving along x
    return {
        "subjectId": subject, "diagnosis": diagnosis, "age": age,
        "hand": "right", "session": 1, "deviceLabel": "iPad Pro 11",
        "trials": [{
            "trial": i + 1, "task": "spiral", "inputType": "pencil",
            "samples": [{"t": float(a), "x": float(a), "y": 0.0, "pressure": 0.5}
                        for a in t],
        } for i in range(n_trials)],
    }


# Check that age_bracket puts each age in the right group, and gives None for no age
def test_age_brackets_split_where_we_say_they_do():
    assert age_bracket(55) == "50s"
    assert age_bracket(59) == "50s"
    assert age_bracket(60) == "60s"
    assert age_bracket(79) == "70s"
    assert age_bracket(80) == "80+"
    assert age_bracket(None) is None


# Check that parse_session gives one record per trial, in order, with the nt subject id
def test_one_record_per_trial():

    # Read a session with 3 trials
    recs = list(parse_session(session(n_trials=3)))

    # Check the count, the trial numbers and the subject ids
    assert len(recs) == 3
    assert [r["trial"] for r in recs] == [1, 2, 3]
    assert all(r["subject_id"] == "nt:a1" for r in recs)


# Check that essential tremor gets label 0 and keeps its diagnosis
def test_diagnosis_is_kept_separately_from_label():

    # Read a session from someone with essential tremor
    rec = next(parse_session(session(diagnosis="essential_tremor")))

    # Check that the label is 0 and the diagnosis is still essential_tremor
    assert rec["label"] == 0
    assert rec["diagnosis"] == "essential_tremor"


# Check that a Parkinson's session gets label 1
def test_parkinsons_is_labeled():
    assert next(parse_session(session(diagnosis="parkinsons")))["label"] == 1


# Check that iter_collected reads every session from one file that holds a list of them
def test_reads_a_file_of_many_sessions(tmp_path):

    # Save 3 sessions into one file
    p = tmp_path / "visit.json"
    p.write_text(json.dumps([session("a1"), session("a2"), session("a3")]))

    # Check that it reads 9 trials from 3 people
    recs = list(iter_collected(tmp_path))
    assert len(recs) == 9
    assert len({r["subject_id"] for r in recs}) == 3


# Check that iter_collected keeps only the trials for the task asked for
def test_skips_other_tasks(tmp_path):

    # Save a session with its first trial changed to writing
    s = session()
    s["trials"][0]["task"] = "writing"
    (tmp_path / "s.json").write_text(json.dumps(s))

    # Check that it finds 2 spiral trials and 1 writing trial
    assert len(list(iter_collected(tmp_path, task="spiral"))) == 2
    assert len(list(iter_collected(tmp_path, task="writing"))) == 1


# Check that points with no pressure read as pressure 0
def test_missing_pressure_reads_zero_not_crash():

    # Remove the pressure from every point
    s = session()
    for tr in s["trials"]:
        for smp in tr["samples"]:
            del smp["pressure"]

    # Check that every pressure comes back as 0
    assert np.all(next(parse_session(s))["pressure"] == 0.0)
