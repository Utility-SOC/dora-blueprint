"""Drill verdict against recovery objectives (drills/lib/verdict.py, gap G3)."""
import json
from pathlib import Path

import pytest

from conftest import REPO, load_module

verdict = load_module("verdict", "drills/lib/verdict.py")


def rec(**kw):
    base = {"verdict": "pass", "integrity_check": "pass",
            "target_rto_seconds": 300, "target_rpo_seconds": 3600,
            "measured_rto_seconds": 120, "measured_rpo_records_lost": 71}
    base.update(kw)
    return {k: v for k, v in base.items() if v is not None}


def test_within_targets_passes_with_no_reasons():
    assert verdict.evaluate(rec()) == ("pass", [])


@pytest.mark.parametrize("rto,expected", [(300, "pass"), (301, "fail")])
def test_rto_boundary_equal_is_pass(rto, expected):
    assert verdict.evaluate(rec(measured_rto_seconds=rto))[0] == expected


@pytest.mark.parametrize("lost,expected", [(3600, "pass"), (3601, "fail")])
def test_rpo_from_records_boundary(lost, expected):
    v, reasons = verdict.evaluate(rec(measured_rpo_records_lost=lost))
    assert v == expected
    if expected == "fail":
        assert "3601 records x 1s" in reasons[0]


def test_measured_rpo_seconds_takes_precedence_over_records():
    v, reasons = verdict.evaluate(rec(measured_rpo_seconds=4000, measured_rpo_records_lost=1))
    assert v == "fail" and "RPO 4000s (measured)" in reasons[0]


def test_integrity_failure_fails_even_within_targets():
    v, reasons = verdict.evaluate(rec(integrity_check="fail"))
    assert v == "fail" and reasons == ["integrity check: fail"]


def test_negative_records_lost_fails():
    v, reasons = verdict.evaluate(rec(measured_rpo_records_lost=-34657))
    assert v == "fail" and "impossible negative data loss" in reasons[0]


def test_every_failure_is_reported_not_just_the_first():
    v, reasons = verdict.evaluate(rec(integrity_check="fail", measured_rto_seconds=900,
                                      measured_rpo_records_lost=5000))
    assert v == "fail" and len(reasons) == 3


def test_missing_targets_are_not_assessed_but_never_silent():
    v, reasons = verdict.evaluate(rec(target_rto_seconds=None, target_rpo_seconds=None))
    assert v == "pass"
    assert reasons == ["not assessed: no target_rto_seconds", "not assessed: no target_rpo_seconds"]


def test_missing_measurement_against_a_target_fails():
    v, reasons = verdict.evaluate(rec(measured_rto_seconds=None))
    assert v == "fail" and "no measured_rto_seconds" in reasons[0]


def test_timeout_is_preserved():
    v, reasons = verdict.evaluate(rec(verdict="timeout"))
    assert v == "timeout" and reasons[0] == "workflow timed out"


def test_enrich_keeps_workflow_verdict_and_overrides_on_target_breach(valid_record):
    enrich = load_module("enrich", "drills/lib/enrich.py")
    out = enrich.enrich(dict(valid_record, target_rto_seconds=60))
    assert out["recovery_verdict"] == "pass"
    assert out["verdict"] == "fail"
    assert out["verdict_reasons"] == ["RTO 120s exceeds target 60s", "not assessed: no target_rpo_seconds"]


def test_enrich_turns_negative_rpo_into_a_loud_failure_not_a_crash(valid_record):
    enrich = load_module("enrich", "drills/lib/enrich.py")
    out = enrich.enrich(dict(valid_record, measured_rpo_records_lost=-34657))
    assert "measured_rpo_records_lost" not in out
    assert out["measured_rpo_records_lost_raw"] == -34657
    assert out["integrity_check"] == "fail" and out["verdict"] == "fail"


def test_existing_samples_reevaluate_without_error():
    """Every committed ns-restore sample can be re-evaluated; the negative-RPO one fails (G15)."""
    results = {}
    for p in sorted((REPO / "docs/evidence/samples").glob("ns-restore-*.json")):
        r = json.loads(p.read_text())
        raw = r.get("measured_rpo_records_lost")
        results[p.name] = verdict.evaluate(r, raw)[0]
    assert results["ns-restore-20260729135024.json"] == "fail"
    assert results["ns-restore-20260728152755.json"] == "pass"
