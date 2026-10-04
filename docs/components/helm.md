# Helm

> **In one sentence:** The package manager for Kubernetes: a way to install a whole product from a versioned bundle called a chart.

| | |
|---|---|
| **Category** | Cluster foundation |
| **Tier** | core |
| **Pinned version** | host-installed |
| **Where it lives** | [`apps/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/), [`bootstrap/install.sh`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/install.sh) |

## What it is, in plain English

Installing a product like Grafana on Kubernetes needs a dozen objects wired together. A **Helm chart** bundles them with a set of adjustable settings ("values"). You pin a chart version and supply values; Helm renders the final YAML.

## Why it is here

Most third-party components here are installed from charts. Pinning the chart version in git makes upgrades deliberate and reviewable. [Argo CD](argo-cd.md) renders the charts itself; `install.sh` uses Helm directly only for Cilium, which has to exist before Argo CD can run.

## How this repository uses it

- Each file in `apps/core/` and `apps/full/` names a chart repository, a chart and a pinned `targetRevision`, with settings under `helm.valuesObject`.
- A test fails if any chart version is floating (`HEAD`, `*`, `latest`, `^`, `~`).

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9(4)(e); NIST CM-3 (change management) | Pinned, reviewable versions | [`tests/test_repo_consistency.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_repo_consistency.py) |
| DORA Art. 28-30 | Chart sources feed the generated Register of Information | [`images/generate-roi.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/images/generate-roi.py) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Installing or upgrading charts fails. Running components are unaffected.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- `helm template` is how several silent chart bugs were confirmed, such as Grafana's `extraVolumes` quietly turning a secret volume into an `emptyDir`.

## Official documentation

- [Helm documentation](https://helm.sh/docs/)
- [Chart best practices](https://helm.sh/docs/chart_best_practices/)
- [Argo CD with Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)

## Related pages

- [Argo CD](argo-cd.md)
