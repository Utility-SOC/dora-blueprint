# Tools and products

One page per technology. Each explains what the thing is in plain English, why it was chosen,
how this repository uses it, which controls it supports, what breaks if it fails, and links to
its official documentation so you can go deeper than these pages do.

!!! tip "Reading order for newcomers"
    [Kubernetes](kubernetes.md), then [Talos](talos.md), [Argo CD](argo-cd.md), [Cilium](cilium.md),
    [Kyverno](kyverno.md), [Velero](velero.md), then whichever interests you.

## Cluster foundation

| Tool | What it does here | Tier |
|---|---|---|
| [Kubernetes](kubernetes.md) | The system that decides which programs run on which machines and keeps them running. | core |
| [Talos Linux](talos.md) | A minimal operating system built only to run Kubernetes, with no shell and no SSH. | core |
| [Docker](docker.md) | The tool that runs the lab's three 'servers' as containers on one machine, and runs the offline CA ceremony. | core |
| [Helm](helm.md) | The package manager for Kubernetes: a way to install a whole product from a versioned bundle called a chart. | core |
| [Argo CD](argo-cd.md) | A robot that keeps the running cluster identical to what is written in git, and puts it back if someone changes it by hand. | core |

## Security enforcement

| Tool | What it does here | Tier |
|---|---|---|
| [Cilium (and Hubble)](cilium.md) | The network layer that blocks all traffic between parts of the platform unless a rule explicitly allows it. | core |
| [Kyverno](kyverno.md) | The gatekeeper that inspects every new workload and refuses insecure ones before they start. | core |
| [cert-manager and the offline CA](cert-manager.md) | Issues and renews the TLS certificates that let internal services trust each other, signed by a private two-level certificate authority. | core |
| [SOPS and age](sops-age.md) | Lets secrets live encrypted in git, readable only by whoever holds the private key. | core |
| [Tetragon](tetragon.md) | Watches what programs actually execute on the nodes, using eBPF, and reports it as logs. | full |
| [Trivy Operator and the findings exporter](trivy-operator.md) | Continuously scans every running container image for known vulnerabilities and records how long each has been open. | full |

## Identity

| Tool | What it does here | Tier |
|---|---|---|
| [Keycloak (and PostgreSQL)](keycloak.md) | The single sign-on server: log in once, and every connected tool knows who you are and which groups you belong to. | full |
| [OpenLDAP and LDAP Account Manager](openldap-lam.md) | A directory of people and groups (the 'phone book' Keycloak reads), plus a web screen for editing it. | full |

## Observability and detection

| Tool | What it does here | Tier |
|---|---|---|
| [Loki](loki.md) | The searchable store for every log line the platform produces. | core |
| [Grafana Alloy](alloy.md) | The courier that collects logs from every pod (and the API audit log) and delivers them to Loki. | core |
| [Grafana (dashboards and Alerting)](grafana.md) | The screens (dashboards) and the alarm rules that decide when something bad has happened. | core |

## Backup and storage

| Tool | What it does here | Tier |
|---|---|---|
| [Velero](velero.md) | Takes scheduled backups of Kubernetes applications and their data, and restores them on demand. | core |
| [MinIO](minio.md) | An in-cluster, Amazon-S3-compatible object store that holds the backups. | core |
| [Storage provisioners (local-path and OpenEBS LocalPV)](storage.md) | Hand out disk space to applications that ask for it; two are used because only one kind can be backed up. | core |

## Drills and incident response

| Tool | What it does here | Tier |
|---|---|---|
| [Argo Workflows](argo-workflows.md) | Runs each drill as a real, recorded multi-step job inside the cluster, instead of a script on someone's laptop. | core |
| [GLPI (and MariaDB)](glpi.md) | A self-hosted IT service-management tool where every drill opens a real incident ticket. | core |
| [The canary workload (and SQLite)](canary.md) | A tiny stand-in application that writes one tamper-evident row per second, so any lost or corrupted data is countable. | core |
| [The drill framework (Python)](drill-framework.md) | The small Python programs that validate a drill record, classify the incident, and compute the reporting deadlines. | core |

## Supply chain

| Tool | What it does here | Tier |
|---|---|---|
| [Sigstore and cosign](sigstore-cosign.md) | Signs software and files without anyone holding a long-lived secret key, and records each signature in a public log. | CI + core (verification) |
| [apko, Wolfi and the SBOM](apko-wolfi.md) | Builds a very small container image from a declarative list of packages, and lists exactly what is inside it. | CI |
| [GitHub Actions](github-actions.md) | The automation that builds images, anchors evidence, runs the tests and builds these docs. | CI |

## Evidence and compliance tooling

| Tool | What it does here | Tier |
|---|---|---|
| [The evidence pipeline](evidence-pipeline.md) | Turns a folder of evidence files into per-control folders, a tamper-evidence chain, an OSCAL export and a readable report. | docs/evidence |
| [OSCAL](oscal.md) | NIST's machine-readable format for saying 'this evidence supports this control', so tools can exchange compliance data. | docs/evidence |
| [MITRE ATT&CK](mitre-attack.md) | A public catalogue of how real attackers behave, used here to label what each alert actually detects. | docs |

## Build, test and documentation

| Tool | What it does here | Tier |
|---|---|---|
| [pytest and the offline test suite](testing.md) | Several hundred automated checks that run in seconds with no cluster, catching logic bugs and documentation drift. | repo |
| [MkDocs Material](mkdocs.md) | Turns the Markdown in `docs/` into a searchable website. | repo |

## Planned, not built

| Tool | What it does here | Tier |
|---|---|---|
| [kube-bench (planned)](kube-bench.md) | Would check the cluster against the CIS Kubernetes Benchmark; not built yet. | not built |

## A note on versions

Versions are pinned in the manifests (Helm chart versions in `apps/`, image tags in
`infrastructure/`, tool versions in `bootstrap/install.sh`). These pages name the pin *at the
time of writing*; the manifests are the authority, and a test fails if a chart is left
unpinned.
