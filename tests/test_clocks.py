"""Regulatory notification clocks (drills/lib/clocks.py).

Mapping: DORA Art. 19 (initial notification: 4h after classification, capped at 24h after
detection) and NIS2 Art. 23 (early warning: 24h after awareness; detection stands in)."""
from datetime import datetime, timedelta, timezone


def test_nis2_is_detect_plus_24h(clocks):
    out = clocks.compute_clocks("2026-01-01T10:00:00Z", None)
    assert out == {"t_notify_due_nis2": "2026-01-02T10:00:00Z"}


def test_dora_is_classify_plus_4h_when_inside_the_cap(clocks):
    out = clocks.compute_clocks("2026-01-01T10:00:00Z", "2026-01-01T11:00:00Z")
    assert out["t_notify_due_dora"] == "2026-01-01T15:00:00Z"


def test_dora_is_capped_at_detect_plus_24h_for_late_classification(clocks):
    out = clocks.compute_clocks("2026-01-01T10:00:00Z", "2026-01-02T09:00:00Z")
    assert out["t_notify_due_dora"] == "2026-01-02T10:00:00Z"
    # The cap makes the two regimes converge exactly here.
    assert out["t_notify_due_dora"] == out["t_notify_due_nis2"]


def test_dora_never_later_than_nis2_when_classified_within_24h(clocks):
    detect = datetime(2026, 1, 1, tzinfo=timezone.utc)
    for hours in range(0, 25, 3):
        classify = detect + timedelta(hours=hours)
        out = clocks.compute_clocks(clocks._format(detect), clocks._format(classify))
        assert out["t_notify_due_dora"] <= out["t_notify_due_nis2"]


def test_delayed_classification_restarts_the_4h_window(clocks):
    """Delegated Reg. (EU) 2025/301: classified as major >24h after awareness -> 4h from
    classification. The 24h cap would otherwise yield a deadline already in the past."""
    out = clocks.compute_clocks("2026-01-01T10:00:00Z", "2026-01-02T16:00:00Z")
    assert out["t_notify_due_dora"] == "2026-01-02T20:00:00Z"
    assert out["t_notify_due_dora"] > out["t_notify_due_nis2"]


def test_classification_exactly_at_the_cap_boundary(clocks):
    out = clocks.compute_clocks("2026-01-01T10:00:00Z", "2026-01-02T10:00:00Z")
    assert out["t_notify_due_dora"] == "2026-01-02T10:00:00Z"


def test_missing_detect_omits_both_deadlines_rather_than_fabricating(clocks):
    assert clocks.compute_clocks(None, "2026-01-01T11:00:00Z") == {}
    assert clocks.compute_clocks("", "2026-01-01T11:00:00Z") == {}


def test_offset_timestamps_are_normalised_to_utc(clocks):
    out = clocks.compute_clocks("2026-01-01T12:00:00+02:00", None)
    assert out["t_notify_due_nis2"] == "2026-01-02T10:00:00Z"
