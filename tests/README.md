# Tests

Everything here runs offline in about three seconds: `make test` (or `python -m pytest`).
No cluster, network, or decryption key is needed.

| File | What it protects | Regulatory/control anchor |
|---|---|---|
| `test_classify.py` | Incident classification logic, thresholds, and the "primary + one other" combination rule | DORA Art. 18 |
| `test_clocks.py` | Notification deadline maths, the 24h cap, and omitting deadlines when detection is missing | DORA Art. 19, NIS2 Art. 23 |
| `test_emit_and_enrich.py` | Drill-record schema validation and enrichment; hand-rolled validator vs real `jsonschema` | DORA Art. 24-27 (evidence quality) |
| `test_canary.py` | The SQLite hash chain detects edits and deleted rows | DORA Art. 12, ISO A.8.13 |
| `test_evidence.py` | Evidence hash chain, manifest hygiene, per-control folders, OSCAL export | NIST AU-9/SI-7, ISO A.8.15, OSCAL |
| `test_generators.py` | Register of Information, GLPI ticket text, host-posture honesty, every Markdown link | DORA Art. 28-30, Art. 13 |
| `test_repo_consistency.py` | Scenario wiring, Argo apps, pinned versions, secrets hygiene, shell syntax | BUILD-SPEC P1 |

## What these tests cannot prove

They check logic and consistency, not behaviour on a live cluster. Anything that needs Talos,
Cilium, Velero, or Kyverno actually running (drills, admission denials, detection latency) is
evidenced by the committed samples in `docs/evidence/samples/`, not by this suite.

## Known deviations pinned on purpose

Two historical evidence samples don't match the current drill-record schema. They are
hash-chained, so they are not edited; `KNOWN_SCHEMA_DEVIATIONS` in `test_repo_consistency.py`
records exactly what is wrong and why. Any *new* deviation fails the suite.
