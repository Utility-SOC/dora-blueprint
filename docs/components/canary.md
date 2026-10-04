# The canary workload (and SQLite)

> **In one sentence:** A tiny stand-in application that writes one tamper-evident row per second, so any lost or corrupted data is countable.

| | |
|---|---|
| **Category** | Drills and incident response |
| **Tier** | core |
| **Pinned version** | image built by this repo (apko/Wolfi, Python 3.13) |
| **Where it lives** | [`apps/core/canary.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/canary.yaml), [`canary/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/canary/), [`images/canary-writer/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/images/canary-writer/) |

## What it is, in plain English

A **canary** is a deliberately simple program placed where you can watch it for early warning. This one inserts a row into a **SQLite** database file once per second; each row's hash covers the previous row's hash, so any gap, edit or truncation is detectable by recomputation.

## Why it is here

To *measure* data loss you need data whose history you know exactly. Counting rows after a restore gives RPO in records. Re-verifying the chain gives the integrity check that catches an empty or wrong restore.

## How this repository uses it

- `writer.py` appends rows; `verify.py` recomputes the chain and exits non-zero on failure.
- Runs in the `canary` namespace, which stands in for the example tenant's workload.
- Has a PodDisruptionBudget and its own Cilium policy.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 11, 12; ISO A.8.13; NIST CP-9, CP-10 | Measurable RPO and integrity-verified recovery | [ns-restore-20260728152755.json](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Drills have nothing to measure.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- Without a `/bin/sh` the image could not support `credential-compromise` at all, so `busybox` was added.
- The package was private on GHCR and the cluster could not pull it. It was made public after scanning for secrets. As of the last CHANGELOG entry the pod had been in `ImagePullBackOff`.

## Limits and honest caveats

- It is a toy. It proves the *mechanism*, not that a real payments database would recover.

## Official documentation

- [SQLite documentation](https://www.sqlite.org/docs.html)
- [Python hashlib](https://docs.python.org/3/library/hashlib.html)

## Related pages

- [Velero](velero.md)
- [Reading the evidence](../guide/reading-the-evidence.md)
