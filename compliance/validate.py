#!/usr/bin/env python3
"""Validate the capability layer and every framework mapping.

Checks: JSON Schema conformance, unique ids, every implemented_by/evidence path exists, every
roadmap id exists in docs/roadmap/README.md, and every mapping references a known capability.
Run: make capabilities-check
"""
import json
import re
import sys
from pathlib import Path

import jsonschema
import yaml

REPO = Path(__file__).resolve().parents[1]
CAPS = REPO / "compliance/capabilities/capabilities.yaml"
MAP_DIR = REPO / "compliance/mappings"


def roadmap_ids():
    text = (REPO / "docs/roadmap/README.md").read_text()
    ids = set(re.findall(r"^\| (T\d+[a-c]?|F\d+|X\d+) ", text, re.M))
    ids |= set(re.findall(r"\| (D\d) \|", text))
    for rng in re.findall(r"^\| ((?:F|X)\d+)([a-z])–([a-z]) ", text, re.M):
        ids |= {rng[0] + chr(c) for c in range(ord(rng[1]), ord(rng[2]) + 1)}
    return ids


def main():
    errors = []
    caps_doc = yaml.safe_load(CAPS.read_text())
    jsonschema.validate(caps_doc, json.loads((CAPS.parent / "schema.json").read_text()))
    known_roadmap = roadmap_ids()
    cap_ids = set()
    for c in caps_doc["capabilities"]:
        if c["id"] in cap_ids:
            errors.append(f"duplicate capability id {c['id']}")
        cap_ids.add(c["id"])
        for p in c.get("implemented_by", []) + c.get("evidence", []):
            if not (REPO / p).exists():
                errors.append(f"{c['id']}: path does not exist: {p}")
        for r in c.get("roadmap", []):
            if not r.startswith("Phase") and r not in known_roadmap:
                errors.append(f"{c['id']}: unknown roadmap id {r}")

    map_schema = json.loads((MAP_DIR / "schema.json").read_text())
    used = set()
    for f in sorted(MAP_DIR.glob("*.yaml")):
        doc = yaml.safe_load(f.read_text())
        try:
            jsonschema.validate(doc, map_schema)
        except jsonschema.ValidationError as e:
            errors.append(f"{f.name}: {e.message}")
            continue
        seen = set()
        for m in doc["mappings"]:
            if m["control"] in seen:
                errors.append(f"{f.name}: duplicate control {m['control']}")
            seen.add(m["control"])
            if m["basis"] == "official" and not m.get("source_ref"):
                errors.append(f"{f.name} {m['control']}: official mapping needs source_ref")
            for cid in m["capabilities"]:
                if cid not in cap_ids:
                    errors.append(f"{f.name} {m['control']}: unknown capability {cid}")
                used.add(cid)

    by_status = {}
    for c in caps_doc["capabilities"]:
        by_status[c["status"]] = by_status.get(c["status"], 0) + 1
    print(f"{len(cap_ids)} capabilities {by_status}; "
          f"{len(list(MAP_DIR.glob('*.yaml')))} mapping file(s); {len(used)} capabilities referenced")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
