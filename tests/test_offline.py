#!/usr/bin/env python3
"""Checks that need no cluster -- `make test`, and CI on every PR (.github/workflows/offline-checks.yaml).

Everything else in this repo is verified against a live cluster; these are the parts that
can regress silently between live runs: the canary's RPO arithmetic, committed evidence
samples against their own schema, and the shell embedded in drill WorkflowTemplates.
"""
import hashlib
import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
EVIDENCE = REPO / "docs" / "evidence"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


emit = load_module("emit", REPO / "drills" / "lib" / "emit.py")


def write_chain(db: Path, start: datetime, count: int, first_ts_offset: int = 0) -> None:
    """Rows exactly as canary/writer.py writes them, one per second from `start`."""
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE canary (counter INTEGER PRIMARY KEY, ts TEXT, prev_hash TEXT, hash TEXT)")
    prev = "0" * 64
    for counter in range(1, count + 1):
        ts = (start + timedelta(seconds=counter - 1 + first_ts_offset)).isoformat()
        h = hashlib.sha256(f"{counter}|{ts}|{prev}".encode()).hexdigest()
        conn.execute("INSERT INTO canary VALUES (?, ?, ?, ?)", (counter, ts, prev, h))
        prev = h
    conn.commit()
    conn.close()


def verify(db: Path, *args: str) -> str:
    out = subprocess.run(
        [sys.executable, str(REPO / "canary" / "verify.py"), *args],
        env={**os.environ, "CANARY_DB_PATH": str(db)}, capture_output=True, text=True,
    )
    return out.stdout.strip()


class CanaryRpo(unittest.TestCase):
    T0 = datetime(2026, 7, 29, 13, 0, 0, tzinfo=timezone.utc)

    def test_post_restore_writes_are_not_counted_as_recovered(self):
        with tempfile.TemporaryDirectory() as d:
            db = Path(d) / "canary.db"
            # 100 rows existed at the fault (t_inject = T0+100s); the restored copy holds the
            # first 60, then its writer appended 30 more after coming back up.
            write_chain(db, self.T0, 90)
            conn = sqlite3.connect(db)
            conn.execute("UPDATE canary SET ts = ? WHERE counter > 60",
                         ((self.T0 + timedelta(seconds=200)).isoformat(),))
            conn.commit()
            conn.close()
            t_inject = (self.T0 + timedelta(seconds=100)).strftime("%Y-%m-%dT%H:%M:%SZ")
            self.assertEqual(verify(db, "--field", "max_counter"), "90")
            self.assertEqual(verify(db, "--field", "max_counter_before", "--before", t_inject), "60")

    def test_lineage_fingerprint_distinguishes_chains(self):
        with tempfile.TemporaryDirectory() as d:
            a, b, a2 = Path(d) / "a.db", Path(d) / "b.db", Path(d) / "a2.db"
            write_chain(a, self.T0, 50)
            write_chain(b, self.T0, 50, first_ts_offset=3600)  # a fresh PVC, an hour later
            write_chain(a2, self.T0, 10)                         # same history, shorter
            self.assertNotEqual(verify(a, "--field", "first_hash"), verify(b, "--field", "first_hash"))
            self.assertEqual(verify(a, "--field", "first_hash"), verify(a2, "--field", "first_hash"))

    def test_nothing_before_cutoff_is_zero_not_blank(self):
        with tempfile.TemporaryDirectory() as d:
            db = Path(d) / "canary.db"
            write_chain(db, self.T0, 5)
            self.assertEqual(verify(db, "--field", "max_counter_before", "--before", "2020-01-01T00:00:00Z"), "0")


class EvidenceSamples(unittest.TestCase):
    def test_drill_records_validate_or_declare_a_known_defect(self):
        schema = emit.load_schema()
        manifest = yaml.safe_load((EVIDENCE / "manifest.yaml").read_text())
        declared = {a["path"]: a.get("known_defect") for a in manifest["artifacts"]}
        scenarios = [p.stem for p in (REPO / "drills" / "scenarios").glob("*.yaml")]
        records = [p for p in sorted((EVIDENCE / "samples").glob("*.json"))
                   if any(p.name.startswith(f"{s}-") for s in scenarios)]
        self.assertTrue(records, "no drill record samples found")
        for sample in records:
            rel = f"samples/{sample.name}"
            with self.subTest(sample=rel):
                errors = emit.validate(json.loads(sample.read_text()), schema)
                if declared.get(rel):
                    self.assertTrue(errors, f"{rel} declares a known_defect but now validates -- drop the declaration")
                else:
                    self.assertFalse(errors, f"{rel} fails the drill record schema: {errors}")

    def test_integrity_chain_matches_committed_samples(self):
        out = subprocess.run([sys.executable, str(EVIDENCE / "chain.py"), "--verify"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)


class ShellSyntax(unittest.TestCase):
    def bash_n(self, script: str, label: str) -> None:
        out = subprocess.run(["bash", "-n"], input=script, capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, f"{label}: {out.stderr}")

    def test_workflow_template_scripts_parse(self):
        for path in sorted((REPO / "drills" / "templates").glob("*.yaml")):
            for doc in yaml.safe_load_all(path.read_text()):
                if not doc or doc.get("kind") not in ("WorkflowTemplate", "CronWorkflow"):
                    continue
                spec = doc["spec"].get("workflowSpec", doc["spec"])
                for tmpl in spec.get("templates", []):
                    container = tmpl.get("container") or tmpl.get("script") or {}
                    for i, arg in enumerate(container.get("args") or []):
                        with self.subTest(template=f"{path.name}:{tmpl['name']}"):
                            self.bash_n(arg, f"{path.name}:{tmpl['name']} arg {i}")

    def test_repo_shell_scripts_parse(self):
        for path in sorted(REPO.glob("**/*.sh")):
            if ".git" in path.parts:
                continue
            with self.subTest(script=str(path.relative_to(REPO))):
                self.bash_n(path.read_text(), str(path.relative_to(REPO)))


if __name__ == "__main__":
    unittest.main()
