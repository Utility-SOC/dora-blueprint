#!/usr/bin/env python3
"""DORA Art. 18 RTS classification-as-code — build-spec §6.5.

Implements a SIMPLIFIED approximation of Commission Delegated Regulation (EU) 2024/1772's
major-incident classification criteria and combination logic — not a verbatim transcription
of the RTS. The numeric thresholds below are illustrative, chosen to be the right rough order
of magnitude, not researched to the letter of the regulation; consult the actual RTS for any
real compliance use. This mirrors the same "simplified framework" discipline
docs/00-scope.md §0.3 already applies to DORA Art. 16 eligibility.

Two of the seven RTS criteria are computed from real, measured `drill-record.schema.json`
fields:
  - duration/downtime, from `measured_rto_seconds`
  - data losses, from `integrity_check` and `measured_rpo_records_lost`

The rest (clients/counterparts affected, geographical spread, economic impact, reputational
impact, critical-service impact) come from `classification-profiles.json`, a per-scenario
synthetic profile — lab fixtures for the platform's example tenant, not measurements of a real
business, per docs/04-limitations.md's own existing note on this file.

Combination logic (simplified, approximating RTS Art. 3): major if the "clients affected" OR
"reputational impact" criterion trips, AND at least one other criterion also trips. A single
tripped criterion alone is not sufficient — this mirrors the RTS's actual combination
requirement, just without reproducing its full criteria table.
"""
import json
import sys
from pathlib import Path

PROFILES_PATH = Path(__file__).parent / "classification-profiles.json"

# Illustrative thresholds -- see module docstring. Not a transcription of the real RTS.
DURATION_THRESHOLD_SECONDS = 2 * 3600
CLIENTS_AFFECTED_PCT_THRESHOLD = 10.0
GEOGRAPHICAL_SPREAD_THRESHOLD = 2  # member states
ECONOMIC_IMPACT_EUR_THRESHOLD = 100_000
REPUTATIONAL_IMPACT_TRIPPED = {"medium", "high"}


def load_profile(scenario: str) -> dict:
    profiles = json.loads(PROFILES_PATH.read_text())
    profile = profiles.get(scenario)
    if profile is None:
        raise KeyError(f"no classification profile for scenario {scenario!r} in {PROFILES_PATH}")
    return profile


def classify(record: dict, profile: dict) -> tuple[str, list[str]]:
    """Return (classification, criteria_tripped) for a drill record + its synthetic profile."""
    criteria_tripped = []

    # Real, measured criteria.
    duration_seconds = record.get("measured_rto_seconds") or 0
    if duration_seconds > DURATION_THRESHOLD_SECONDS:
        criteria_tripped.append("duration")

    rpo_records_lost = record.get("measured_rpo_records_lost") or 0
    data_loss = record.get("integrity_check") == "fail" or rpo_records_lost > 0
    if data_loss:
        criteria_tripped.append("data_losses")

    # Synthetic criteria, from the per-scenario profile.
    if profile["clients_affected_pct"] > CLIENTS_AFFECTED_PCT_THRESHOLD:
        criteria_tripped.append("clients_counterparties_affected")

    if profile["geographical_spread_member_states"] >= GEOGRAPHICAL_SPREAD_THRESHOLD:
        criteria_tripped.append("geographical_spread")

    if profile["economic_impact_eur"] > ECONOMIC_IMPACT_EUR_THRESHOLD:
        criteria_tripped.append("economic_impact")

    if profile["reputational_impact"] in REPUTATIONAL_IMPACT_TRIPPED:
        criteria_tripped.append("reputational_impact")

    if profile["critical_service_affected"]:
        criteria_tripped.append("critical_services_affected")

    primary_criteria = {"clients_counterparties_affected", "reputational_impact"}
    tripped_set = set(criteria_tripped)
    primary_tripped = bool(tripped_set & primary_criteria)
    other_tripped = len(tripped_set - primary_criteria)
    classification = "major" if primary_tripped and other_tripped >= 1 else "non-major"

    return classification, criteria_tripped


if __name__ == "__main__":
    raw = sys.stdin.read()
    record = json.loads(raw)
    profile = load_profile(record["scenario"])
    classification, criteria_tripped = classify(record, profile)
    print(json.dumps({"classification": classification, "classification_criteria_tripped": criteria_tripped}))
