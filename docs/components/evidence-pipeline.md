# The evidence pipeline

> **In one sentence:** Turns a folder of evidence files into per-control folders, a tamper-evidence chain, an OSCAL export and a readable report.

| | |
|---|---|
| **Category** | Evidence and compliance tooling |
| **Tier** | docs/evidence |
| **Pinned version** | Python scripts in the repo |
| **Where it lives** | [`docs/evidence/manifest.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/manifest.yaml), [`docs/evidence/collect.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/collect.py), [`docs/evidence/chain.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/chain.py), [`docs/evidence/oscal.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/oscal.py), [`docs/evidence/report.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/report.py) |

## What it is, in plain English

`manifest.yaml` is the single source of truth: each evidence file is listed once with tags such as `dora:art-11` or `nist80053:cp-9`. `make evidence` runs four scripts over it: `collect.py` copies files into `by-control/<framework>/<control>/`, `chain.py` builds the hash chain, `oscal.py` writes an OSCAL JSON file, and `report.py` writes `report.md`.

## Why it is here

One artifact often satisfies several controls across several frameworks. Tagging once and generating the views avoids copy-paste drift, which is exactly what auditors catch.

## How this repository uses it

- Five tag namespaces: `dora`, `nis2`, `iso27001`, `nist80053`, `attack`.
- `by-control/`, `integrity-chain.json`, `oscal-assessment-results.json` and `report.md` are **generated but committed**, so they are browsable on GitHub, and CI compares a fresh regeneration to them.
- Tests check that the manifest, folders, OSCAL file and report all agree.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| NIST AU-9, SI-7; ISO A.8.15 | Tamper-evident evidence store | [`tests/test_evidence.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_evidence.py) |
| All frameworks | Single tagging source for every mapping | [`docs/evidence/manifest.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/manifest.yaml) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Views go stale, and the stale-view tests fail.

## Limits and honest caveats

- Never edit `by-control/`. It is derived output.
- `satisfied` in the OSCAL file means 'this repo claims and evidences it', not an independent finding.

## Official documentation

- [Reading the evidence](../guide/reading-the-evidence.md)
- [OSCAL](oscal.md)
- [PyYAML](https://pyyaml.org/wiki/PyYAMLDocumentation)

## Related pages

- [OSCAL](oscal.md)
- [Sigstore and cosign](sigstore-cosign.md)
