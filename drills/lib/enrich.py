#!/usr/bin/env python3
"""Enriches a raw drill record with classification + regulatory clocks, then re-validates it
through emit.py's own schema check — build-spec §6.5/§6.4, run host-side by run-drill.sh after
the workflow's own record is captured. See classify.py, clocks.py, and the Phase 11 plan's own
note on why this runs outside the workflow pod rather than inside it.
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import classify  # noqa: E402
import clocks  # noqa: E402
import emit  # noqa: E402


def enrich(record: dict) -> dict:
    profile = classify.load_profile(record["scenario"])
    classification, criteria_tripped = classify.classify(record, profile)
    record["classification"] = classification
    record["classification_criteria_tripped"] = criteria_tripped

    t_classify = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    record["t_classify"] = t_classify
    record.update(clocks.compute_clocks(record.get("t_detect"), t_classify))

    schema = emit.load_schema()
    errors = emit.validate(record, schema)
    if errors:
        print(json.dumps({"drill_record_emit_error": True, "errors": errors, "record": record}), file=sys.stderr)
        sys.exit(1)

    return record


if __name__ == "__main__":
    raw_record = json.loads(sys.stdin.read())
    print(json.dumps(enrich(raw_record)))
