#!/usr/bin/env python3
"""Validate and emit a drill record — build-spec §6.6.

Deliberately dependency-free (stdlib only): this runs inside whatever minimal image
Phase 6 builds for the drill workflows, and pulling in the full `jsonschema` package
for a schema this flat isn't worth the extra dependency surface. The validation below
covers required fields, types, and enums — everything `drill-record.schema.json`
actually constrains — not general JSON Schema semantics.

Emission is a single JSON line to stdout. There is no separate "ship to the log sink"
step: Alloy already collects every pod's stdout via the Kubernetes API
(infrastructure/observability/alloy) and forwards it to Loki. A drill record becomes
evidence by being logged, the same way any other pod's output does — see
build-spec §6.7 for why *retention and deletion controls* on that path matter, which
is a Phase 8 concern, not this file's.
"""
import json
import sys
from pathlib import Path

SCHEMA_PATH = Path(__file__).parent.parent / "schema" / "drill-record.schema.json"

_TYPE_MAP = {
    "string": str,
    "integer": int,
    "array": list,
    "object": dict,
    "boolean": bool,
}


def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text())


def validate(record: dict, schema: dict) -> list[str]:
    errors = []
    properties = schema["properties"]

    for key in schema.get("required", []):
        if key not in record:
            errors.append(f"missing required field: {key}")

    for key, value in record.items():
        prop = properties.get(key)
        if prop is None:
            errors.append(f"unknown field: {key}")
            continue

        expected_type = prop.get("type")
        py_type = _TYPE_MAP.get(expected_type)
        if py_type and not isinstance(value, py_type):
            errors.append(f"{key}: expected {expected_type}, got {type(value).__name__}")

        enum = prop.get("enum")
        if enum and value not in enum:
            errors.append(f"{key}: {value!r} not in {enum}")

        if expected_type == "integer" and isinstance(value, int) and prop.get("minimum") is not None:
            if value < prop["minimum"]:
                errors.append(f"{key}: {value} below minimum {prop['minimum']}")

    return errors


def emit(record: dict) -> int:
    """Validate `record`, print it as one JSON line, return the process exit code.

    A drill record that fails to validate is itself printed too (build-spec §6.2:
    "A drill that fails to emit a record is itself a control failure and should
    alert" — the failure needs to be visible in the log stream, not swallowed).
    """
    schema = load_schema()
    errors = validate(record, schema)

    if errors:
        print(json.dumps({"drill_record_emit_error": True, "errors": errors, "record": record}))
        return 1

    print(json.dumps(record))
    return 0


if __name__ == "__main__":
    raw = sys.stdin.read()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(json.dumps({"drill_record_emit_error": True, "errors": [f"invalid JSON on stdin: {exc}"]}))
        sys.exit(1)
    sys.exit(emit(parsed))
