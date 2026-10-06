"""Intermediate and final reporting deadlines (drills/lib/clocks.py, roadmap T10, gap G12).

Every expected value below was computed by hand from the rules in clocks.LEGAL_BASIS.
"""
from datetime import datetime, timezone

import pytest

from conftest import load_module

clocks = load_module("clocks", "drills/lib/clocks.py")
DETECT = "2026-01-01T10:00:00Z"


def test_normal_classification_assumes_on_time_submission():
    out = clocks.compute_report_deadlines(DETECT, "2026-01-01T11:00:00Z")
    assert out["t_intermediate_due_dora"] == "2026-01-04T15:00:00Z"   # initial 15:00 + 72h
    assert out["t_final_due_dora"] == "2026-02-04T15:00:00Z"          # intermediate + 1 month
    assert out["t_notification_due_nis2"] == "2026-01-04T10:00:00Z"   # awareness + 72h
    assert out["t_final_due_nis2"] == "2026-02-04T10:00:00Z"          # notification + 1 month
    assert out["deadline_basis"].startswith("assumed on-time submission")


def test_delayed_classification_shifts_every_dora_deadline():
    """Classified 48h after awareness: initial = classify + 4h, and later reports follow it."""
    out = clocks.compute_report_deadlines(DETECT, "2026-01-03T10:00:00Z")
    assert out["t_intermediate_due_dora"] == "2026-01-06T14:00:00Z"
    assert out["t_final_due_dora"] == "2026-02-06T14:00:00Z"
    # NIS2 runs from awareness and is unaffected by when classification happened.
    assert out["t_notification_due_nis2"] == "2026-01-04T10:00:00Z"


def test_recorded_submissions_are_used_instead_of_assumptions():
    out = clocks.compute_report_deadlines(
        DETECT, "2026-01-01T11:00:00Z",
        t_initial_submitted="2026-01-01T12:00:00Z",
        t_intermediate_submitted="2026-01-03T09:00:00Z",
        t_notification_submitted_nis2="2026-01-02T10:00:00Z")
    assert out["t_intermediate_due_dora"] == "2026-01-04T12:00:00Z"
    assert out["t_final_due_dora"] == "2026-02-03T09:00:00Z"
    assert out["t_final_due_nis2"] == "2026-02-02T10:00:00Z"
    assert out["deadline_basis"] == "recorded submissions"


def test_partial_submissions_say_exactly_what_was_assumed():
    out = clocks.compute_report_deadlines(DETECT, "2026-01-01T11:00:00Z",
                                          t_initial_submitted="2026-01-01T12:00:00Z")
    assert "initial notification" not in out["deadline_basis"]
    assert "intermediate report submitted at its deadline" in out["deadline_basis"]


@pytest.mark.parametrize("start,expected", [
    ((2026, 1, 31), (2026, 2, 28)),   # non-leap February clamps
    ((2028, 1, 31), (2028, 2, 29)),   # leap year
    ((2026, 3, 31), (2026, 4, 30)),
    ((2026, 12, 31), (2027, 1, 31)),  # year rollover
    ((2026, 2, 15), (2026, 3, 15)),
])
def test_one_month_is_a_calendar_month_clamped_to_month_end(start, expected):
    got = clocks.add_months(datetime(*start, 9, 30, tzinfo=timezone.utc))
    assert (got.year, got.month, got.day, got.hour, got.minute) == (*expected, 9, 30)


def test_month_end_rollover_flows_into_the_final_deadline():
    out = clocks.compute_report_deadlines("2026-01-28T20:00:00Z", "2026-01-28T21:00:00Z")
    # initial 2026-01-29T01:00, intermediate 2026-02-01T01:00, final 2026-03-01T01:00
    assert out["t_intermediate_due_dora"] == "2026-02-01T01:00:00Z"
    assert out["t_final_due_dora"] == "2026-03-01T01:00:00Z"


def test_no_detect_means_no_basis_and_nothing_invented():
    assert clocks.compute_report_deadlines(None, "2026-01-01T11:00:00Z") == {}


def test_no_classification_gives_nis2_only():
    out = clocks.compute_report_deadlines(DETECT, None)
    assert "t_intermediate_due_dora" not in out and "t_final_due_dora" not in out
    assert out["t_notification_due_nis2"] == "2026-01-04T10:00:00Z"


def test_every_emitted_deadline_has_a_stated_legal_basis():
    out = clocks.compute_report_deadlines(DETECT, "2026-01-01T11:00:00Z")
    out.update(clocks.compute_clocks(DETECT, "2026-01-01T11:00:00Z"))
    for key in out:
        if key.startswith("t_"):
            assert key in clocks.LEGAL_BASIS, key
            assert clocks.LEGAL_BASIS[key]["source"] and clocks.LEGAL_BASIS[key]["rule"]


def test_enrich_adds_the_new_deadlines_and_passes_the_schema(valid_record):
    enrich = load_module("enrich", "drills/lib/enrich.py")
    out = enrich.enrich(dict(valid_record, t_detect="2026-01-01T00:01:00Z"))
    for key in ("t_intermediate_due_dora", "t_final_due_dora", "t_notification_due_nis2",
                "t_final_due_nis2", "deadline_basis"):
        assert key in out


def test_ticket_shows_both_regimes_side_by_side_and_flags_unverified_basis():
    incident = load_module("open_incident", "drills/lib/open-incident.py")
    record = {"drill_id": "x", "scenario": "ns-restore", "classification": "major",
              "t_detect": DETECT, "t_classify": "2026-01-01T11:00:00Z"}
    record.update(clocks.compute_clocks(DETECT, record["t_classify"]))
    record.update(clocks.compute_report_deadlines(DETECT, record["t_classify"]))
    text = incident.build_content(record)
    assert "| Report | DORA (binding for this tenant) | NIS2 (comparison) |" in text
    assert "| Initial | 2026-01-01T15:00:00Z | 2026-01-02T10:00:00Z |" in text
    assert "| Intermediate / notification | 2026-01-04T15:00:00Z | 2026-01-04T10:00:00Z |" in text
    assert "| Final | 2026-02-04T15:00:00Z | 2026-02-04T10:00:00Z |" in text
    assert "not yet verified against the Official Journal" in text
    assert "a real DORA Art. 19 notification obligation applies" in text
