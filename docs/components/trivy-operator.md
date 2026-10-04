# Trivy Operator and the findings exporter

> **In one sentence:** Continuously scans every running container image for known vulnerabilities and records how long each has been open.

| | |
|---|---|
| **Category** | Security enforcement |
| **Tier** | full |
| **Pinned version** | chart 0.34.0 |
| **Where it lives** | [`apps/full/trivy-operator.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/trivy-operator.yaml), [`apps/full/trivy-findings-exporter.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/trivy-findings-exporter.yaml), [`infrastructure/trivy-operator/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/trivy-operator/) |

## What it is, in plain English

A **CVE** is a publicly catalogued software vulnerability. **Trivy** compares the contents of a container image to vulnerability databases. **Trivy Operator** runs it continuously inside the cluster: it watches every workload and writes a report object per image. A newly disclosed CVE in an already-running image is found without anyone re-running a scan. The **CISA KEV catalog** lists vulnerabilities known to be actively exploited, which are the ones to fix first.

## Why it is here

NIS2 Art. 21(2)(e) names vulnerability handling, and DORA Art. 25 lists vulnerability scans among required tests. Counting CVEs alone is not management; tracking age against a service-level target, and flagging actively-exploited ones, is.

## How this repository uses it

- A CronJob (every 15 minutes) exports per-image severity counts and one line per CVE (first-detected date, age in days, SLA status, KEV flag) into Loki.
- First-detected dates are stored in a ConfigMap and never overwritten.
- If the KEV fetch fails, `kev_known` is `null` (unknown), never a silent `false`.
- A Grafana 'Vulnerability management' dashboard visualises it.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| NIST RA-5 | Vulnerability monitoring and scanning | Dashboard; no committed evidence sample yet |
| DORA Art. 25; NIS2 21(2)(e) | Vulnerability scanning as a testing activity | Not yet in the evidence manifest |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

No new scans; existing reports remain until stale.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- Cluster compliance reports depended on disabled infra-assessment data and made the sync fail, so that feature is off.
- Trivy's multi-container scan jobs needed a narrowly scoped Kyverno PolicyException ([doc](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/trivy-operator-scan-jobs.md)).

## Limits and honest caveats

- **Not verified end to end on a live cluster.** The exporter's own header says it was tested against synthetic fixtures only. It is flagged as done in the README phase table, so treat this phase as built but unverified live.
- The SLA windows are illustrative, not a policy you have adopted.

## Official documentation

- [Trivy Operator documentation](https://aquasecurity.github.io/trivy-operator/latest/)
- [Trivy](https://trivy.dev/latest/docs/)
- [CISA KEV catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog)
- [CVE program](https://www.cve.org/About/Overview)

## Related pages

- [Loki](loki.md)
- [Grafana](grafana.md)
