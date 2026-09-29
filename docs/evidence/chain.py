#!/usr/bin/env python3
"""Hash chain over docs/evidence/samples/ -- build-spec §6.7/Phase 20 ("A real evidence
file's tamper-evidence property... is independently verifiable, not asserted").

docs/06-operations.md and docs/05-shared-responsibility.md both state the gap this closes
plainly: today's evidence samples are plain git-tracked files, so git history alone is their
only tamper-evidence property. Same mechanism canary/writer.py already uses to prove *its* data
hasn't been silently altered -- each entry's hash commits to its own content and the previous
entry's hash, so any edit, removal, or reorder of a committed sample breaks the chain from that
point forward, exactly the failure mode canary/verify.py already detects for the canary's own
rows.

Scope: docs/evidence/samples/ only (the canonical originals) -- docs/evidence/by-control/ is
collect.py's own derived output (copies of these same files, regenerated on demand), chaining
it too would just be chaining copies of what's already chained here.

`.github/workflows/evidence-integrity.yaml` regenerates this chain on every push touching
samples/ or this script, fails the job if the committed docs/evidence/integrity-chain.json
doesn't match a fresh recomputation (catches "edited evidence without regenerating the chain"),
and cosign-signs the resulting chain_head keylessly -- the same GitHub OIDC -> Fulcio -> Rekor
mechanism Phase 12 already uses for image signing, giving the chain head a public, independently
checkable transparency-log entry rather than relying on git history alone. That signature lives
in the workflow's own artifact/job summary, not in this script -- this script only computes the
chain and writes/verifies integrity-chain.json.
"""
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

EVIDENCE_DIR = Path(__file__).parent
SAMPLES_DIR = EVIDENCE_DIR / "samples"
CHAIN_PATH = EVIDENCE_DIR / "integrity-chain.json"
GENESIS_HASH = "0" * 64


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def entry_hash(rel_path: str, file_hash: str, prev_hash: str) -> str:
    return hashlib.sha256(f"{rel_path}|{file_hash}|{prev_hash}".encode()).hexdigest()


def sample_files() -> list[Path]:
    # Sorted by relative path -- deterministic and needs no trust in filename-embedded
    # timestamps (which describe when a *drill* ran, not when it was chained), not a claim
    # that this order is chronological.
    return sorted(p for p in SAMPLES_DIR.rglob("*") if p.is_file())


def build_chain() -> dict:
    entries = []
    prev = GENESIS_HASH
    for path in sample_files():
        rel = str(path.relative_to(EVIDENCE_DIR))
        fh = sha256_file(path)
        ch = entry_hash(rel, fh, prev)
        entries.append({"path": rel, "file_hash": fh, "chain_hash": ch})
        prev = ch
    return {
        "algorithm": "sha256",
        "genesis": GENESIS_HASH,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "file_count": len(entries),
        "entries": entries,
        "chain_head": prev,
    }


def cmd_generate() -> int:
    chain = build_chain()
    CHAIN_PATH.write_text(json.dumps(chain, indent=2) + "\n", encoding="utf-8")
    print(f"chain_head={chain['chain_head']} file_count={chain['file_count']} -> {CHAIN_PATH}")
    return 0


def cmd_verify() -> int:
    if not CHAIN_PATH.exists():
        print(json.dumps({"integrity_check": "fail", "errors": [f"{CHAIN_PATH} does not exist -- run with no args to generate it first"]}))
        return 1

    committed = json.loads(CHAIN_PATH.read_text(encoding="utf-8"))
    fresh = build_chain()

    errors = []
    committed_by_path = {e["path"]: e for e in committed["entries"]}
    fresh_by_path = {e["path"]: e for e in fresh["entries"]}

    for path, fresh_e in fresh_by_path.items():
        if path not in committed_by_path:
            errors.append(f"{path}: present now but not in the committed chain (added without regenerating)")
        elif committed_by_path[path]["file_hash"] != fresh_e["file_hash"]:
            errors.append(f"{path}: file_hash mismatch (content changed since the chain was generated)")

    for path in committed_by_path:
        if path not in fresh_by_path:
            errors.append(f"{path}: in the committed chain but missing now (removed without regenerating)")

    # Order matters too -- even with identical file_hashes, a reordering changes every
    # downstream chain_hash from that point on, which this final full-chain comparison catches
    # independent of the per-path checks above.
    if committed["entries"] != fresh["entries"] and not errors:
        errors.append("entry order or chain_hash differs from the committed chain despite matching per-file content (reordered)")

    result = {
        "committed_chain_head": committed.get("chain_head"),
        "recomputed_chain_head": fresh["chain_head"],
        "file_count": fresh["file_count"],
        "integrity_check": "pass" if not errors and committed["chain_head"] == fresh["chain_head"] else "fail",
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 0 if result["integrity_check"] == "pass" else 1


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--verify":
        return cmd_verify()
    return cmd_generate()


if __name__ == "__main__":
    raise SystemExit(main())
