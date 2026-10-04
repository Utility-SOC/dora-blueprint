# The drill framework (Python)

> **In one sentence:** The small Python programs that validate a drill record, classify the incident, and compute the reporting deadlines.

| | |
|---|---|
| **Category** | Drills and incident response |
| **Tier** | core |
| **Pinned version** | Python 3.10+ (stdlib only at runtime) |
| **Where it lives** | [`drills/lib/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/lib/), [`drills/schema/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/schema/), [`drills/scenarios/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/scenarios/) |

## What it is, in plain English

Four scripts, each readable in a few minutes: `emit.py` validates a record against a JSON Schema and prints it; `classify.py` decides major or non-major; `clocks.py` computes notification deadlines; `enrich.py` runs the previous two and re-validates; `open-incident.py` makes the GLPI ticket.

## Why it is here

Regulation is turned into code that can be tested. Each function has unit tests. The classification and clocks are the most legally sensitive logic in the repo, so they are the most tested.

## How this repository uses it

- Runtime code is **stdlib only** on purpose, so it runs in a minimal image.
- Classification approximates Delegated Regulation (EU) 2024/1772 with **illustrative thresholds**. Two criteria are measured (duration, data loss) and the rest come from synthetic per-scenario profiles.
- Clocks follow DORA Art. 19 and Delegated Regulation (EU) 2025/301 (including the delayed-classification case, fixed during the test work) and NIS2 Art. 23.
- If `t_detect` is missing both deadlines are omitted, not invented.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 18 | Classification as code | [`tests/test_classify.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_classify.py) |
| DORA Art. 19; NIS2 Art. 23 | Deadlines as code | [`tests/test_clocks.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_clocks.py) |
| DORA Art. 13 | Post-incident review text in the ticket | [incident-response-20260729210627.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/incident-response-20260729210627.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Records are not validated or enriched, and the drill still runs.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- `open-incident.py` once hard-coded the runbook link to `ns-restore` for every scenario.
- The workflow's own `jq` pretty-printed the record and silently broke the single-line extraction. `jq -c` fixed it.
- A `str | None` annotation does not import on Python 3.9 (found when running tests locally).

## Limits and honest caveats

- The thresholds are **not** the RTS's real thresholds. Do not use them for a real classification.
- The 4h/24h model was wrong for delayed classification until this docs pass.

## Official documentation

- [JSON Schema](https://json-schema.org/understanding-json-schema/)
- [Python datetime](https://docs.python.org/3/library/datetime.html)
- [Commission Delegated Regulation (EU) 2025/301 (EUR-Lex)](https://eur-lex.europa.eu/eli/reg_del/2025/301/oj/eng)

## Related pages

- [DORA mapping](../compliance/dora.md)
- [GLPI](glpi.md)
- [pytest and the test suite](testing.md)
