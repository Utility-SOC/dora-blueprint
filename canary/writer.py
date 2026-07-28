#!/usr/bin/env python3
"""Append-only hash-chain writer — build-spec §6.1.

Inserts one row per second into a SQLite table on a PVC. Each row's hash commits to
its own counter, timestamp, and the previous row's hash, so any silent corruption of
a restored volume — the failure mode a naive "did the restore succeed" check misses —
is detectable without needing an external checksum store.
"""
import hashlib
import os
import sqlite3
import time
from datetime import datetime, timezone

DB_PATH = os.environ.get("CANARY_DB_PATH", "/data/canary.db")
GENESIS_HASH = "0" * 64


def row_hash(counter: int, ts: str, prev_hash: str) -> str:
    return hashlib.sha256(f"{counter}|{ts}|{prev_hash}".encode()).hexdigest()


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS canary (
            counter INTEGER PRIMARY KEY,
            ts TEXT NOT NULL,
            prev_hash TEXT NOT NULL,
            hash TEXT NOT NULL
        )
        """
    )
    conn.commit()


def last_row(conn: sqlite3.Connection) -> tuple[int, str] | None:
    cur = conn.execute("SELECT counter, hash FROM canary ORDER BY counter DESC LIMIT 1")
    return cur.fetchone()


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    ensure_schema(conn)

    prev = last_row(conn)
    counter = prev[0] + 1 if prev else 1
    prev_hash = prev[1] if prev else GENESIS_HASH

    print(f"canary writer starting at counter={counter} (resumed={prev is not None})", flush=True)

    while True:
        ts = datetime.now(timezone.utc).isoformat()
        h = row_hash(counter, ts, prev_hash)
        conn.execute(
            "INSERT INTO canary (counter, ts, prev_hash, hash) VALUES (?, ?, ?, ?)",
            (counter, ts, prev_hash, h),
        )
        conn.commit()
        prev_hash = h
        counter += 1
        time.sleep(1)


if __name__ == "__main__":
    main()
