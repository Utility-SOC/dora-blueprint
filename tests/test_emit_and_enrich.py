"""Drill-record schema validation (drills/lib/emit.py) and enrichment (enrich.py)."""
import json

import pytest

from conftest import load_module


def test_valid_record_has_no_errors(emit, valid_record):
    assert emit.validate(valid_record, emit.load_schema()) == []


@pytest.mark.parametrize("field", ["drill_id", "scenario", "verdict", "t_inject", "t_recover"])
def test_missing_required_field_is_reported(emit, valid_record, field):
    del valid_record[field]
    assert f"missing required field: {field}" in emit.validate(valid_record, emit.load_schema())


def test_unknown_field_rejected(emit, valid_record):
    valid_record["surprise"] = 1
    assert "unknown field: surprise" in emit.validate(valid_record, emit.load_schema())


def test_enum_violation(emit, valid_record):
    valid_record["verdict"] = "great"
    assert any("verdict" in e for e in emit.validate(valid_record, emit.load_schema()))


def test_wrong_type(emit, valid_record):
    valid_record["measured_rto_seconds"] = "fast"
    assert any("measured_rto_seconds" in e for e in emit.validate(valid_record, emit.load_schema()))


def test_negative_integer_below_minimum(emit, valid_record):
    valid_record["measured_rto_seconds"] = -1
    assert any("below minimum" in e for e in emit.validate(valid_record, emit.load_schema()))


def test_emit_prints_one_json_line_and_returns_zero(emit, valid_record, capsys):
    assert emit.emit(valid_record) == 0
    out = capsys.readouterr().out.strip().splitlines()
    assert len(out) == 1 and json.loads(out[0]) == valid_record


def test_emit_failure_is_visible_in_the_log_stream(emit, valid_record, capsys):
    del valid_record["verdict"]
    assert emit.emit(valid_record) == 1
    payload = json.loads(capsys.readouterr().out)
    assert payload["drill_record_emit_error"] is True


def test_hand_rolled_validator_agrees_with_real_jsonschema(emit, valid_record):
    """emit.py deliberately avoids the jsonschema dependency; make sure that shortcut never
    diverges from the real thing on the cases it claims to cover."""
    jsonschema = pytest.importorskip("jsonschema")
    schema = emit.load_schema()
    cases = [valid_record]
    bad = dict(valid_record, verdict="nope")
    cases.append(bad)
    extra = dict(valid_record, extra=1)
    cases.append(extra)
    missing = {k: v for k, v in valid_record.items() if k != "scenario"}
    cases.append(missing)
    for rec in cases:
        ours = not emit.validate(rec, schema)
        theirs = jsonschema.Draft202012Validator(schema).is_valid(rec)
        assert ours == theirs, rec


def test_enrich_adds_classification_and_clocks(valid_record):
    enrich = load_module("enrich", "drills/lib/enrich.py")
    valid_record["t_detect"] = "2026-01-01T00:00:06Z"
    out = enrich.enrich(valid_record)
    assert out["classification"] == "non-major"
    assert "t_classify" in out and "t_notify_due_dora" in out and "t_notify_due_nis2" in out


def test_enrich_without_detect_has_no_deadlines(valid_record):
    enrich = load_module("enrich", "drills/lib/enrich.py")
    out = enrich.enrich(valid_record)
    assert "t_notify_due_nis2" not in out and "t_notify_due_dora" not in out
