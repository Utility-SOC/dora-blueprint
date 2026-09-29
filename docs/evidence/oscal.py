#!/usr/bin/env python3
"""Generates docs/evidence/oscal-assessment-results.json from manifest.yaml -- Phase 27
("real OSCAL JSON generated from the evidence manifest").

Structure checked against a real NIST-published example (usnistgov/oscal-content's
examples/ar/json/ifa_assessment-results-example-min.json, OSCAL 1.1.2), not guessed from
memory -- this generates the same shape: assessment-results -> {uuid, metadata, import-ap,
results[]}, one observation + one finding per (artifact, control tag) pair.

What this is NOT, stated plainly (build-spec P8's "say so, don't fake it" discipline, same as
images/generate-roi.py's DORA RTS disclaimer): a full OSCAL Assessment Plan/Results workflow.
There is no real oscal Assessment Plan document behind import-ap.href -- it points at
manifest.yaml itself, this repo's actual source of scope/evidence mapping, with a remark saying
so plainly. No `subjects` reference real OSCAL component-definition/SSP documents this repo
doesn't have; each observation's subject is a single stand-in identifying the platform itself,
not a per-component inventory. Every finding's target.status is "satisfied" -- this generates a
positive evidence record from what this repo already asserts and evidences elsewhere
(manifest.yaml, docs/03-control-matrix.md), not an independent audit that could find "not
satisfied".

UUIDs are uuid5-derived (namespace + a stable seed string per object), not uuid4-random -- every
observation/finding/result/document UUID is stable across reruns against an unchanged
manifest.yaml, so a diff between two generations only ever shows the legitimate
metadata.last-modified/results[].start run timestamps changing, never a UUID reshuffle --
confirmed by actually running it twice and diffing, not assumed.
"""
import json
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import yaml

EVIDENCE_DIR = Path(__file__).parent
MANIFEST_PATH = EVIDENCE_DIR / "manifest.yaml"
CHAIN_PATH = EVIDENCE_DIR / "integrity-chain.json"
OUTPUT_PATH = EVIDENCE_DIR / "oscal-assessment-results.json"

OSCAL_VERSION = "1.1.2"
NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "https://github.com/Utility-SOC/dora-blueprint")

TIMESTAMP_RE = re.compile(r"(\d{14})")


def stable_uuid(seed: str) -> str:
    return str(uuid.uuid5(NAMESPACE, seed))


def collected_at(artifact_path: str) -> str:
    # Most sample filenames carry a trailing YYYYMMDDHHMMSS -- when present, that's a real
    # timestamp of when that specific drill/check ran, more honest than this generator's own
    # run time. Falls back to the chain's generated_at (already computed from these same real
    # files), then to now(), if a filename doesn't carry one.
    m = TIMESTAMP_RE.search(Path(artifact_path).name)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)
            return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            pass
    if CHAIN_PATH.exists():
        chain = json.loads(CHAIN_PATH.read_text(encoding="utf-8"))
        return chain.get("generated_at", _now())
    return _now()


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build(manifest: dict) -> dict:
    artifacts = manifest["artifacts"]
    now = _now()

    platform_component_uuid = stable_uuid("component:dora-blueprint-platform")

    observations = []
    findings = []
    observation_uuid_by_path: dict[str, str] = {}

    for artifact in artifacts:
        path = artifact["path"]
        obs_uuid = stable_uuid(f"observation:{path}")
        observation_uuid_by_path[path] = obs_uuid
        collected = collected_at(path)
        observations.append({
            "uuid": obs_uuid,
            "title": Path(path).name,
            "description": artifact["description"],
            "methods": ["EXAMINE"],
            "types": ["finding"],
            "subjects": [{"subject-uuid": platform_component_uuid, "type": "component"}],
            "relevant-evidence": [{
                "href": path,
                "description": artifact["description"],
            }],
            "collected": collected,
        })

        for tag in artifact["tags"]:
            findings.append({
                "uuid": stable_uuid(f"finding:{path}:{tag}"),
                "title": f"Evidence for {tag}",
                "description": artifact["description"],
                "target": {
                    "type": "objective-id",
                    "target-id": tag,
                    "description": f"Control tag {tag}, per docs/03-control-matrix.md / docs/06-nist-800-53-crosswalk.md / docs/07-attack-mapping.md (see manifest.yaml's own tag-namespace comment for which doc each prefix maps to).",
                    "status": {"state": "satisfied"},
                },
                "related-observations": [{"observation-uuid": obs_uuid}],
            })

    result = {
        "uuid": stable_uuid(f"result:{len(artifacts)}:{sorted(observation_uuid_by_path)}"),
        "title": "dora-blueprint generated assessment results",
        "description": (
            "Generated from docs/evidence/manifest.yaml's real artifact-to-control-tag mapping "
            "by docs/evidence/oscal.py -- one observation per real evidence artifact, one "
            "finding per (artifact, control tag) pair. Regenerate after any manifest.yaml change."
        ),
        "start": now,
        "reviewed-controls": {
            "control-selections": [{"description": "All control tags present in manifest.yaml at generation time; see target-id on each finding."}],
        },
        "observations": observations,
        "findings": findings,
    }

    return {
        "assessment-results": {
            "uuid": stable_uuid(f"assessment-results:{len(artifacts)}"),
            "metadata": {
                "title": "dora-blueprint Generated Assessment Results",
                "last-modified": now,
                "version": now[:10],
                "oscal-version": OSCAL_VERSION,
                "remarks": (
                    "Generated, not hand-authored -- a representative subset of the OSCAL "
                    "assessment-results model covering the same substantive relationships "
                    "(evidence artifact -> observation -> finding -> control) as a full "
                    "Assessment Plan/Results workflow would, not a verbatim implementation "
                    "of one. Every finding's status is 'satisfied' because this reflects what "
                    "this repo already asserts and evidences elsewhere (manifest.yaml, "
                    "docs/03-control-matrix.md), not an independent audit. See "
                    "docs/04-limitations.md."
                ),
            },
            "import-ap": {
                "href": "../manifest.yaml",
                "remarks": (
                    "Not a real OSCAL Assessment Plan document -- there isn't one in this repo. "
                    "Points at manifest.yaml, this repo's actual source of evidence scope/mapping, "
                    "stated plainly rather than fabricating a compliant-looking AP this generator "
                    "doesn't really have."
                ),
            },
            "results": [result],
        }
    }


def main() -> int:
    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))
    doc = build(manifest)
    OUTPUT_PATH.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    n_artifacts = len(manifest["artifacts"])
    n_observations = len(doc["assessment-results"]["results"][0]["observations"])
    n_findings = len(doc["assessment-results"]["results"][0]["findings"])
    print(f"{n_artifacts} artifacts -> {n_observations} observations, {n_findings} findings -> {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
