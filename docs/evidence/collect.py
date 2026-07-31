#!/usr/bin/env python3
"""Generates docs/evidence/by-control/<tag>/ from manifest.yaml.

Real file copies, not symlinks -- this repo moves between a Windows checkout and a Linux
runner (appserv), where symlinks are a real source of cross-platform pain, and copies are
simply regenerated idempotently on each run rather than needing to stay in sync by hand.
by-control/ is fully derived output: never edit it directly, edit manifest.yaml and re-run.
"""
import shutil
import sys
from pathlib import Path

import yaml

EVIDENCE_DIR = Path(__file__).parent
MANIFEST_PATH = EVIDENCE_DIR / "manifest.yaml"
OUTPUT_DIR = EVIDENCE_DIR / "by-control"


def main() -> int:
    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))
    artifacts = manifest["artifacts"]

    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)

    tag_counts: dict[str, int] = {}
    missing: list[str] = []

    for artifact in artifacts:
        src = EVIDENCE_DIR / artifact["path"]
        if not src.exists():
            missing.append(artifact["path"])
            continue
        for tag in artifact["tags"]:
            dest_dir = OUTPUT_DIR / tag.replace(":", "/")
            dest_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest_dir / src.name)
            tag_counts[tag] = tag_counts.get(tag, 0) + 1

    if missing:
        print("ERROR: manifest references paths that don't exist:", file=sys.stderr)
        for path in missing:
            print(f"  - {path}", file=sys.stderr)
        return 1

    print(f"{len(artifacts)} artifacts, {sum(tag_counts.values())} placements across {len(tag_counts)} control tags")
    for tag in sorted(tag_counts):
        print(f"  {tag}: {tag_counts[tag]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
