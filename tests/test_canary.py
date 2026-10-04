"""Canary hash chain (canary/writer.py + canary/verify.py) against a real SQLite file.
Mapping: DORA Art. 12 / ISO A.8.13 -- detecting silent corruption of a restored volume."""
import json
import sqlite3
import subprocess
import sys

import pytest

from conftest import REPO, load_module

GENESIS = "0" * 64


@pytest.fixture
def writer():
    return load_module("writer", "canary/writer.py")


@pytest.fixture
def db(tmp_path, writer):
    path = tmp_path / "canary.db"
    conn = sqlite3.connect(path)
    writer.ensure_schema(conn)
    prev = GENESIS
    for counter in range(1, 6):
        ts = f"2026-01-01T00:00:0{counter}+00:00"
        h = writer.row_hash(counter, ts, prev)
        conn.execute("INSERT INTO canary VALUES (?,?,?,?)", (counter, ts, prev, h))
        prev = h
    conn.commit()
    conn.close()
    return path


def verify(db_path, *args):
    proc = subprocess.run(
        [sys.executable, str(REPO / "canary" / "verify.py"), *args],
        env={"CANARY_DB_PATH": str(db_path), "PATH": ""},
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout.strip()


def test_row_hash_is_deterministic_and_input_sensitive(writer):
    a = writer.row_hash(1, "t", GENESIS)
    assert a == writer.row_hash(1, "t", GENESIS)
    assert a != writer.row_hash(2, "t", GENESIS)
    assert a != writer.row_hash(1, "u", GENESIS)
    assert a != writer.row_hash(1, "t", "1" * 64)


def test_last_row_empty_then_populated(writer, db, tmp_path):
    empty = sqlite3.connect(tmp_path / "e.db")
    writer.ensure_schema(empty)
    assert writer.last_row(empty) is None
    assert writer.last_row(sqlite3.connect(db))[0] == 5


def test_clean_chain_passes(db):
    code, out = verify(db)
    result = json.loads(out)
    assert code == 0 and result["integrity_check"] == "pass"
    assert result["row_count"] == 5 and result["max_counter"] == 5


def test_tampered_timestamp_is_detected(db):
    conn = sqlite3.connect(db)
    conn.execute("UPDATE canary SET ts='2030-01-01T00:00:00+00:00' WHERE counter=3")
    conn.commit()
    code, out = verify(db)
    assert code == 1
    assert any("counter 3" in e and "hash mismatch" in e for e in json.loads(out)["errors"])


def test_deleted_row_is_detected_as_a_gap(db):
    conn = sqlite3.connect(db)
    conn.execute("DELETE FROM canary WHERE counter=3")
    conn.commit()
    code, out = verify(db)
    assert code == 1
    assert any("counter gap" in e for e in json.loads(out)["errors"])


def test_field_flag_prints_only_that_field(db):
    code, out = verify(db, "--field", "max_counter")
    assert (code, out) == (0, "5")


def test_empty_database_passes_vacuously(tmp_path, writer):
    path = tmp_path / "empty.db"
    conn = sqlite3.connect(path)
    writer.ensure_schema(conn)
    conn.close()
    code, out = verify(path)
    assert code == 0 and json.loads(out)["row_count"] == 0
