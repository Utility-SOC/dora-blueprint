# Grafana Alloy

> **In one sentence:** The courier that collects logs from every pod (and the API audit log) and delivers them to Loki.

| | |
|---|---|
| **Category** | Observability and detection |
| **Tier** | core |
| **Pinned version** | chart 1.11.0 |
| **Where it lives** | [`apps/core/alloy.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/alloy.yaml), [`infrastructure/observability/alloy-rbac/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/observability/alloy-rbac/), [`bootstrap/host-log-shipper/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/host-log-shipper/) |

## What it is, in plain English

A **log shipper** is an agent that reads logs where they are produced and forwards them. **Alloy** is Grafana's current collector. It replaces Promtail, which is in maintenance-only mode upstream.

## Why it is here

Without it there is nothing for Grafana to alert on. It is chosen to read pod logs through the Kubernetes API rather than node files, which sidesteps the fact Talos has no `/var/lib/docker/containers`.

## How this repository uses it

- Pod logs via `loki.source.kubernetes`, which needs extra RBAC for `pods/log` (separate Application source).
- A control-plane-pinned **DaemonSet** reads the API server audit **file** (`/var/log/audit/kube/`), which needed a Talos bind mount.
- `bootstrap/host-log-shipper/` ships the separate 'appserv' host's logs into the same Loki.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 10; NIST AU-2 | Collects the audit and runtime streams that detection watches | [detection-latency-20260729135024.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

New logs stop flowing; stored logs remain.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The audit log is a *file*, not stdout, so Alloy had to change from a Deployment to a pinned DaemonSet plus a mount.
- The chart's default RBAC lacked `pods/log`.

## Limits and honest caveats

- Alloy's audit-log access needs a documented Kyverno exception ([doc](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/alloy-audit-log.md)).

## Official documentation

- [Alloy documentation](https://grafana.com/docs/alloy/latest/)
- [loki.source.kubernetes](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.kubernetes/)

## Related pages

- [Loki](loki.md)
- [Tetragon](tetragon.md)
