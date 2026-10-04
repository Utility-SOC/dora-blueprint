# Loki

> **In one sentence:** The searchable store for every log line the platform produces.

| | |
|---|---|
| **Category** | Observability and detection |
| **Tier** | core |
| **Pinned version** | chart 7.1.0 |
| **Where it lives** | [`apps/core/loki.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/loki.yaml) |

## What it is, in plain English

A **log** is a line of text a program writes about what it did. **Loki** (from Grafana Labs) stores huge volumes of logs cheaply by indexing only a few labels (namespace, app) and storing the text compressed. You query it with **LogQL**, for example 'show every line from the `canary` namespace containing `delete`'.

## Why it is here

Detection needs data to look at. A pipeline from every pod into one queryable place means drill records, audit events and process events can all be searched and alerted on the same way. Drill records become evidence simply by being logged.

## How this repository uses it

- `SingleBinary` mode with filesystem storage on a persistent volume, with no dependency on MinIO so its failure domain is independent of backup and restore.
- Stores drill records, Kubernetes audit events, Tetragon events and Trivy findings.
- A 10 MB `max_line_size` was needed to keep `RequestResponse`-level audit entries.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 10; NIST AU-2, AU-6 | Event logging and review | [detection-latency-20260729135024.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt) |
| ISO A.8.15 (logging) | Central, queryable audit and event log | [Alloy and Loki config](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/loki.yaml) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Logs stop being stored, and alerts that query Loki see nothing. (Drills still run, but `t_detect` would be unset, not invented.)

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- A bare `| json` parse tripped Loki's 500-series limit, so queries use explicit field extraction.
- A bare `| unwrap` is rejected. It needs `max_over_time(... | unwrap field [range]) by (...)`.
- The default 256 KB line limit silently dropped the secrets and RBAC-change audit entries this logging exists to capture.

## Limits and honest caveats

- No retention policy suited to compliance record-keeping. Disk size is the real limit. Logs in Loki are *not* write-once; the tamper-evidence mechanism applies to the evidence samples, not to all logs.

## Official documentation

- [Loki documentation](https://grafana.com/docs/loki/latest/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
- [Deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/)

## Related pages

- [Alloy](alloy.md)
- [Grafana](grafana.md)
