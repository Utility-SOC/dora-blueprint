# OSCAL

> **In one sentence:** NIST's machine-readable format for saying 'this evidence supports this control', so tools can exchange compliance data.

| | |
|---|---|
| **Category** | Evidence and compliance tooling |
| **Tier** | docs/evidence |
| **Pinned version** | OSCAL 1.1.2 (assessment-results subset) |
| **Where it lives** | [`docs/evidence/oscal.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/oscal.py), [`docs/evidence/oscal-assessment-results.json`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/oscal-assessment-results.json) |

## What it is, in plain English

**OSCAL** (Open Security Controls Assessment Language) is a set of JSON/XML/YAML formats published by NIST for control catalogs, system security plans, assessment plans and assessment *results*. Instead of a PDF, a tool can read the data.

## Why it is here

Auditors and GRC platforms increasingly accept OSCAL. Generating it from the manifest means it cannot drift from the evidence.

## How this repository uses it

- `oscal.py` emits an `assessment-results` document: one **observation** per evidence file and one **finding** per (artifact, control) pair.
- UUIDs are derived deterministically (uuid5), so regenerating an unchanged manifest gives identical IDs.
- The structure was checked against a real NIST example, not recalled from memory.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| NIST CA-2, CA-7 (assessment, monitoring) | Machine-readable assessment output | [`oscal-assessment-results.json`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/oscal-assessment-results.json) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

No OSCAL export. Nothing else changes.

## Limits and honest caveats

- A **representative subset**, not a full implementation. `import-ap` points at `manifest.yaml`, not a real assessment plan.
- Every finding says `satisfied`. This is a self-assertion, not an independent audit, and the file's own remarks say so.

## Official documentation

- [OSCAL home](https://pages.nist.gov/OSCAL/)
- [Assessment results model](https://pages.nist.gov/OSCAL/learn/concepts/layer/assessment/assessment-results/)
- [NIST OSCAL content](https://github.com/usnistgov/oscal-content)

## Related pages

- [Evidence pipeline](evidence-pipeline.md)
- [NIST 800-53 mapping](../compliance/nist80053.md)
