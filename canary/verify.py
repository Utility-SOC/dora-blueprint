#!/usr/bin/env python3
"""Hash-chain integrity check for the canary — build-spec §6.1/§6.6.

Recomputes every row's hash from (counter, ts, prev_hash) and confirms the chain is
unbroken. Prints a one-line JSON summary and exits 0 on a clean chain, 1 otherwise —
designed to be both human-readable (`kubectl exec ... -- python3.13 verify.py`) and
machine-readable (Phase 3's drill emitter reuses this for `integrity_check` and to
compute measured_rpo_records_lost from the reported max counter).

`--before <iso8601>` adds `max_counter_before`: the highest counter written strictly before
that instant. Restore drills pass their own t_inject, so rows the restored writer appends
after coming back up don't count as "recovered" -- reading plain max_counter after the
restore was exactly that bug (records lost came back negative, CHANGELOG.md Phase 9).

`first_hash` is the hash of the earliest row: a fingerprint of the chain's lineage. Two
databases with different first_hash values are not the same canary history at all (e.g. the
live canary was recreated on a fresh, empty PVC after the backup was taken), so their
counters can't be subtracted to get an RPO.
"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys
from datetime import datetime

DB_PATH = os.environ.get("CANARY_DB_PATH", "/data/canary.db")
GENESIS_HASH = "0" * 64


def row_hash(counter: int, ts: str, prev_hash: str) -> str:
    return hashlib.sha256(f"{counter}|{ts}|{prev_hash}".encode()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field")
    parser.add_argument("--before", type=datetime.fromisoformat)
    args = parser.parse_args()
    field = args.field

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT counter, ts, prev_hash, hash FROM canary ORDER BY counter ASC").fetchall()

    result = {
        "db_path": DB_PATH,
        "row_count": len(rows),
        "min_counter": rows[0][0] if rows else None,
        "max_counter": rows[-1][0] if rows else None,
        "first_hash": rows[0][3] if rows else None,
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

    if args.before is not None:
        # 0, not None, when nothing predates the cutoff: "no rows recovered" is a real count.
        result["max_counter_before"] = max(
            (c for c, ts, _, _ in rows if datetime.fromisoformat(ts) < args.before), default=0
        )

    if field:
        # Bash-orchestrated callers (drills/scenarios) shell out via `kubectl exec`
        # and don't want to parse JSON on the other side of that pipe.
        print(result.get(field, ""))
    else:
        print(json.dumps(result))
    return 0 if result["integrity_check"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
