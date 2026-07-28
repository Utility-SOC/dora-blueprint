#!/usr/bin/env python3
"""Hash-chain integrity check for the canary — build-spec §6.1/§6.6.

Recomputes every row's hash from (counter, ts, prev_hash) and confirms the chain is
unbroken. Prints a one-line JSON summary and exits 0 on a clean chain, 1 otherwise —
designed to be both human-readable (`kubectl exec ... -- python3 verify.py`) and
machine-readable (Phase 3's drill emitter reuses this for `integrity_check` and to
compute measured_rpo_records_lost from the reported max counter).
"""
import hashlib
import json
import os
import sqlite3
import sys

DB_PATH = os.environ.get("CANARY_DB_PATH", "/data/canary.db")
GENESIS_HASH = "0" * 64


def row_hash(counter: int, ts: str, prev_hash: str) -> str:
    return hashlib.sha256(f"{counter}|{ts}|{prev_hash}".encode()).hexdigest()


def main() -> int:
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT counter, ts, prev_hash, hash FROM canary ORDER BY counter ASC").fetchall()

    result = {
        "db_path": DB_PATH,
        "row_count": len(rows),
        "min_counter": rows[0][0] if rows else None,
        "max_counter": rows[-1][0] if rows else None,
        "integrity_check": "pass",
        "errors": [],
    }

    expected_prev = GENESIS_HASH
    expected_counter = rows[0][0] if rows else None

    for counter, ts, prev_hash, stored_hash in rows:
        if counter != expected_counter:
            result["errors"].append(f"counter gap: expected {expected_counter}, got {counter}")
        if prev_hash != expected_prev:
            result["errors"].append(f"counter {counter}: prev_hash does not chain to prior row")
        recomputed = row_hash(counter, ts, prev_hash)
        if recomputed != stored_hash:
            result["errors"].append(f"counter {counter}: hash mismatch (tampered or corrupted row)")

        expected_prev = stored_hash
        expected_counter = counter + 1

    if result["errors"]:
        result["integrity_check"] = "fail"

    print(json.dumps(result))
    return 0 if result["integrity_check"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
