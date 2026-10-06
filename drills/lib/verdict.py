#!/usr/bin/env python3
"""Drill verdict against the recorded recovery objectives -- DORA Art. 12(6), gap G3.

The workflow templates emit their own `verdict`, which only reflects whether recovery and the
integrity check succeeded. A restore that took 20 minutes against a 5-minute target is not a
pass, so this module re-derives the verdict from the measured values and the record's own
targets, host-side, where it can be unit-tested. The template's original verdict is kept as
`recovery_verdict` by enrich.py.

Rules (equal to a target is a pass):
  - verdict "timeout" from the workflow is preserved as "timeout";
  - integrity_check != "pass"                         -> fail;
  - measured_rto_seconds > target_rto_seconds         -> fail;
  - RPO in seconds > target_rpo_seconds               -> fail, where RPO seconds is
    measured_rpo_seconds when present, otherwise records lost x CANARY_SECONDS_PER_RECORD
    (the canary writes one record per second, canary/writer.py; build-spec section 6.1);
  - a negative records-lost value is physically impossible and always fails (gap G15).
A missing target is not a failure, but is reported as "not assessed" so it can't pass silently.
"""

CANARY_SECONDS_PER_RECORD = 1


def evaluate(record: dict, raw_records_lost: int | None = None) -> tuple[str, list[str]]:
    """Return (verdict, reasons). `raw_records_lost` carries a value removed from the record
    because it failed schema validation (a negative count); see enrich.py."""
    failures: list[str] = []
    notes: list[str] = []

    if record.get("integrity_check") != "pass":
        failures.append(f"integrity check: {record.get('integrity_check', 'missing')}")

    rto, rto_target = record.get("measured_rto_seconds"), record.get("target_rto_seconds")
    if rto_target is None:
        notes.append("not assessed: no target_rto_seconds")
    elif rto is None:
        failures.append("no measured_rto_seconds to compare with the target")
    elif rto > rto_target:
        failures.append(f"RTO {rto}s exceeds target {rto_target}s")

    lost = record.get("measured_rpo_records_lost", raw_records_lost)
    if lost is not None and lost < 0:
        failures.append(f"impossible negative data loss ({lost} records); measurement fault")
    else:
        rpo_target = record.get("target_rpo_seconds")
        if record.get("measured_rpo_seconds") is not None:
            rpo, basis = record["measured_rpo_seconds"], "measured"
        elif lost is not None:
            rpo, basis = lost * CANARY_SECONDS_PER_RECORD, f"{lost} records x {CANARY_SECONDS_PER_RECORD}s"
        else:
            rpo, basis = None, None
        if rpo_target is None:
            notes.append("not assessed: no target_rpo_seconds")
        elif rpo is None:
            failures.append("no RPO measurement to compare with the target")
        elif rpo > rpo_target:
            failures.append(f"RPO {rpo}s ({basis}) exceeds target {rpo_target}s")

    if record.get("verdict") == "timeout":
        return "timeout", ["workflow timed out"] + failures + notes
    return ("fail" if failures else "pass"), failures + notes
