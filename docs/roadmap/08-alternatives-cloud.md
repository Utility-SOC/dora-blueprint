# Track 08: alternatives and cloud equivalents

**Owner direction:** every product in this lab comes with the landscape around it: other projects that could
do the same job, and the managed services on AWS, Azure and GCP. The lab picks one tool per job. The teaching
value is in showing *why* that one, and what a firm in a different situation would pick instead.

**Order:** F01a–F01d in parallel (each covers 8 pages), then F02.

---

## F01 · "Alternatives and cloud equivalents" on every component page

- **Wave / mode:** 5 · offline
- **Depends on:** PR #3 merged (it creates the 32 pages in `docs/components/`)

### The section format (identical on every page, so a test can enforce it)

```markdown
## Alternatives

| Project | Licence | Maturity | Pick it instead when… |
|---|---|---|---|
| Flux | Apache-2.0 | CNCF graduated | you want controllers per concern and no UI; Azure's AKS GitOps extension is Flux-based |

## Managed cloud equivalents

| Cloud | Service | Covers | Does **not** cover (your side of shared responsibility) |
|---|---|---|---|
| AWS | … | … | … |
| Azure | … | … | … |
| GCP | … | … | … |

## FedRAMP / IL5 note

| Cloud service | FedRAMP High | DoD IL5 | Source (retrieved yyyy-mm-dd) |
|---|---|---|---|
| … | yes / no / unverified | yes / no / unverified | link to FedRAMP Marketplace or provider page |

## Why this lab chose <tool>

Two to four sentences. Tie them to the lab's constraints (self-hosted, low RAM, teaching, no cloud account needed).
```

Rules:
- Three to six alternatives. Every licence and maturity claim is checked against the project's own repo or the CNCF landscape,
  with a retrieval date in a page footnote.
- Use a managed service only if it really does the job. If a cloud has no real equivalent, say "no direct equivalent" and
  name the nearest thing.
- The FedRAMP and IL5 columns are **"unverified" unless you found the listing**. Never infer them from a region name.
- Add `docs/components/_template.md` containing exactly this skeleton.

**Seed lists (starting points from planning; verify every entry, and add or remove freely):**

| Page | Open-source alternatives | AWS / Azure / GCP |
|---|---|---|
| talos | Flatcar, Bottlerocket, Kairos, Ubuntu + k3s/RKE2 | EKS (Bottlerocket/AL2023 nodes) / AKS (Azure Linux) / GKE (Container-Optimized OS) |
| kubernetes | RKE2, k3s, OKD/OpenShift, kubeadm | EKS / AKS / GKE |
| cilium | Calico, Antrea, Flannel+NetworkPolicy, Istio ambient (L7/mTLS) | VPC CNI + network policy / Azure CNI powered by Cilium / GKE Dataplane V2 |
| argo-cd | Flux, Rancher Fleet | verify any managed Argo CD offering / AKS GitOps (Flux v2 extension) / Config Sync |
| helm | Kustomize, Timoni, cdk8s, Jsonnet/Tanka | n/a (tooling) |
| docker | Podman, containerd + nerdctl, Talos QEMU provisioner | n/a (local tooling) |
| storage | Longhorn, Rook-Ceph, OpenEBS, local-path | EBS CSI / Azure Disk CSI / Persistent Disk CSI |
| kyverno | OPA Gatekeeper, Kubewarden, built-in ValidatingAdmissionPolicy (CEL) | self-managed on EKS / Azure Policy for AKS / GKE Policy Controller |
| cert-manager | step-ca, Vault/OpenBao PKI, EJBCA, CFSSL | AWS Private CA (+ issuer) / Key Vault certificates / Certificate Authority Service (+ issuer) |
| keycloak | Authentik, Zitadel, Dex, Authelia, Ory | IAM Identity Center or Cognito / Microsoft Entra ID / Cloud Identity or Identity Platform |
| openldap-lam | FreeIPA/389-DS, Samba AD, lldap | AWS Directory Service / Entra Domain Services / Managed Service for Microsoft AD |
| sops-age | Vault/OpenBao + External Secrets Operator, Sealed Secrets, Infisical | Secrets Manager + KMS / Key Vault / Secret Manager + Cloud KMS |
| tetragon | Falco, KubeArmor, Tracee, Wazuh agent | GuardDuty EKS Runtime Monitoring / Defender for Containers / GKE threat detection (SCC) |
| trivy-operator | Grype, Kubescape, Clair | Amazon Inspector / Defender for Containers vulnerability assessment / Artifact Analysis |
| kube-bench | Kubescape, Polaris | Security Hub (CIS EKS) / Defender CSPM / GKE security posture |
| apko-wolfi | Distroless, Chainguard Images, UBI-micro, Alpine, Iron Bank (IL5 context) | ECR / ACR / Artifact Registry (as registries) |
| sigstore-cosign | Notation (Notary v2), in-toto, GitHub artifact attestations | AWS Signer / Notation + Key Vault (Trusted Signing) / Binary Authorization |
| github-actions | GitLab CI, Tekton, Jenkins, Woodpecker | CodeBuild/CodePipeline / Azure Pipelines / Cloud Build |
| velero | Kasten K10, KubeStash, CloudCasa, Trilio | AWS Backup for EKS / Azure Backup for AKS / Backup for GKE |
| minio | Ceph RGW, SeaweedFS, Garage | S3 (+ Object Lock) / Blob Storage (+ immutability) / Cloud Storage (+ bucket lock) |
| argo-workflows | Tekton, LitmusChaos, Chaos Mesh, Temporal | AWS FIS (+ Resilience Hub) / Azure Chaos Studio / verify GCP options |
| alloy | OpenTelemetry Collector, Fluent Bit, Vector | CloudWatch agent / Azure Monitor Agent / Ops Agent |
| loki | OpenSearch, ClickHouse, VictoriaLogs, Graylog | CloudWatch Logs or OpenSearch Service / Log Analytics (+ Sentinel) / Cloud Logging (+ Google SecOps) |
| grafana | OpenSearch Dashboards, Perses | Amazon Managed Grafana / Azure Managed Grafana / Cloud Monitoring dashboards |
| glpi | iTop, Zammad, Znuny, Request Tracker | Systems Manager Incident Manager / Sentinel incidents / Google SecOps SOAR cases (none is a full ITSM; ServiceNow is the usual SaaS answer) |
| canary | Grafana k6, Checkly, Blackbox exporter | CloudWatch Synthetics / Application Insights availability tests / Cloud Monitoring uptime checks |
| drill-framework | LitmusChaos, Chaos Mesh, Steadybit | AWS FIS + Resilience Hub / Azure Chaos Studio / verify GCP options |
| evidence-pipeline | compliance-trestle, Lula, OpenSCAP results | Audit Manager / Defender for Cloud regulatory compliance + Purview Compliance Manager / Security Command Center compliance + Assured Workloads |
| oscal | compliance-trestle, Lula, NIST OSCAL CLI, FedRAMP automation repo | (same as above; all three expose some OSCAL; verify) |
| mitre-attack | Sigma, ATT&CK Navigator, D3FEND | GuardDuty / Defender / SCC finding-to-ATT&CK mappings |
| mkdocs | Docusaurus, Hugo, Sphinx, Antora | n/a |
| testing | bats (shell), kyverno CLI tests, Chainsaw, conftest | n/a |

### Sub-tasks, one session each

- **F01a:** talos, kubernetes, cilium, argo-cd, helm, docker, storage, kyverno
- **F01b:** cert-manager, keycloak, openldap-lam, sops-age, tetragon, trivy-operator, kube-bench, apko-wolfi
- **F01c:** sigstore-cosign, github-actions, velero, minio, argo-workflows, alloy, loki, grafana
- **F01d:** glpi, canary, drill-framework, evidence-pipeline, oscal, mitre-attack, mkdocs, testing

**Tests** (added by whichever sub-task lands first; the rest extend it): every page in `docs/components/` except `index.md`
and `_template.md` has the four headings, the "Managed cloud equivalents" table has AWS, Azure and GCP rows, and the
FedRAMP/IL5 table cells use only `yes`, `no`, `unverified` or `n/a`.

**Done when (each sub-task):** its 8 pages are complete, the test covers them, and `mkdocs build --strict` passes.

---

## F02 · AWS, Azure and GCP reference architectures

- **Wave / mode:** 5 · offline
- **Depends on:** F01a–d

**Files:** `docs/architecture/index.md`, `aws.md`, `azure.md`, `gcp.md`.

**Steps:**
1. `index.md` holds a layer table. Rows: cluster, network policy, admission, PKI, identity, secrets, log collection,
   SIEM, runtime detection, vulnerability management, backup and DR, chaos and resilience testing, ITSM, evidence and
   compliance automation, and supply-chain signing. Columns: this lab, AWS, Azure, GCP. Link each cell to the F01 page.
2. Each provider page has:
   - a Mermaid diagram of the same platform built from that provider's managed services;
   - what you gain (operations offloaded, inherited controls) and what you lose (portability, transparency, cost);
   - the provider's **compliance-automation** services and which framework packs they offer for ISO 27001, NIST 800-53,
     FedRAMP High, DoD IL5 and DORA, each verified against current provider documentation with a retrieval date;
   - the government region story: AWS GovCloud (US), Azure Government, and Google Cloud's Assured Workloads for US
     government, with their IL5 status verified;
   - EU data residency and sovereignty options relevant to Irish firms (e.g. EU regions, sovereign-cloud offerings),
     verified;
   - **Art. 28/30 lens:** using managed services makes the provider an ICT third party, possibly a designated critical
     provider. Show what lands in the Register of Information (link T30).
3. Add a short "why this lab is self-hosted" note: no cloud account needed, everything is inspectable, and it teaches
   the mechanism rather than the console.

**Done when:** all four pages are in the nav and Mermaid renders in the strict build.
