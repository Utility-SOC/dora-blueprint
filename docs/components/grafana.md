# Grafana (dashboards and Alerting)

> **In one sentence:** The screens (dashboards) and the alarm rules that decide when something bad has happened.

| | |
|---|---|
| **Category** | Observability and detection |
| **Tier** | core |
| **Pinned version** | chart 10.5.15 |
| **Where it lives** | [`apps/core/grafana.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/grafana.yaml), [`infrastructure/observability/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/observability/) |

## What it is, in plain English

**Grafana** draws charts from data sources such as Loki. **Grafana Alerting** evaluates a query on a schedule and, if a condition holds, fires an alert. Both are defined as files here, not clicked together.

## Why it is here

DORA Art. 10 asks for mechanisms to promptly detect anomalous activity and for automatic alerts. Critically, **`t_detect` comes from Grafana's own alert state**, not from the drill script, so detection is independently observed.

## How this repository uses it

- Two real alert rules: `canary-ns-delete-detect` (a namespace delete in the audit log, ATT&CK T1485) and `canary-shell-spawn-detect` (a shell execed in the canary, T1059.004). Each carries ATT&CK annotations.
- Drills poll Grafana's alert API with a Viewer-scoped token over TLS verified against the platform CA.
- Dashboards: drill trends (RTO/RPO), platform overview, security detection, vulnerability management.
- OIDC login through [Keycloak](keycloak.md) when the `full` tier is deployed.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 10; ISO A.8.16; NIST SI-4, AU-6 | Alert rules with measured latency | [detection-latency-20260729135024.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt) |
| MITRE ATT&CK T1485, T1059.004 | Rules tagged with the techniques they observe | [ATT&CK mapping](../07-attack-mapping.md) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

No alerts fire, so `t_detect` stays unset. Two early drills genuinely failed to detect and left it unset rather than fabricated, and that failure is left in the record.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- A 60-second lookback was too tight for real shipping and evaluation latency (about 66 s). It was widened to 3 minutes.
- Alert thresholds reject range results ('only reduced data can be alerted on'), so queries are `instant`.
- Pinning a datasource `uid` conflicted with persisted state and crash-looped pods.
- `extraVolumes` silently became an `emptyDir`. `extraSecretMounts` is what works.

## Limits and honest caveats

- Measured detection latency (6 s, 11 s) are single runs.
- Grafana's database is not meant to be durable, and a rebuild loses UI-only changes.

## Official documentation

- [Grafana documentation](https://grafana.com/docs/grafana/latest/)
- [Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)

## Related pages

- [Loki](loki.md)
- [Tetragon](tetragon.md)
- [ATT&CK mapping](../07-attack-mapping.md)
