# NIST SP 800-53 Rev 5 crosswalk

A toy-scoped crosswalk, not full 800-53 coverage — see `BUILD-SPEC.md` §12 for why a full
~1000-control catalog isn't attemptable for a reference architecture like this one. The goal
here is different from `docs/03-control-matrix.md`'s DORA/NIS2/ISO rows: those track a specific
regulated tenant's obligations; this tracks how the same real, already-built platform mechanisms
also satisfy a second, independent framework — reusing evidence, not re-building anything.

**Scope note:** the PE (Physical and Environmental Protection) family is out of scope entirely —
this platform is assumed deployed on a cloud provider, where physical security is the provider's
responsibility, not this platform's. PS (Personnel Security) rows are mostly marked
not-applicable: this is a solo-built reference architecture, not a staffed operation. Where a
row's real-world implementation genuinely depends on having more than one person (separation of
duties, independent review), documentation assumes **three operators** — a platform lead, a
security/compliance lead, and an on-call responder — purely so role-separation controls can be
described honestly rather than hand-waved. No control here is more mature than what real,
running infrastructure actually demonstrates; rows without a real implementation are marked
`not yet generated`, same discipline as the DORA/NIS2/ISO matrix.

| Control | Requirement | Implemented by | Evidence | Status |
|---|---|---|---|---|
| AC-2 | Account Management | `infrastructure/keycloak/`, `infrastructure/openldap/` | [`docs/evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt`](evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt) — real LDAP-federated accounts, real groups claim | generated |
| AC-3 | Access Enforcement | `argocd-cm`/`argocd-rbac-cm` OIDC+RBAC config | [`docs/evidence/samples/argocd-rbac-verification-20260729045300.txt`](evidence/samples/argocd-rbac-verification-20260729045300.txt) — a real API authorization decision distinguishing an admin role from a read-only one | generated |
| AT-2 | Literacy Training and Awareness | — | toy awareness artifact | not yet generated — Phase 22 follow-up |
| AU-2 | Event Logging | `apps/loki.yaml`/Alloy, kube-apiserver audit policy | [`docs/evidence/samples/detection-latency-20260729135024.txt`](evidence/samples/detection-latency-20260729135024.txt) | generated |
| AU-6 | Audit Record Review, Analysis, and Reporting | `apps/grafana.yaml` Alerting rules on the kube-audit stream | [`docs/evidence/samples/detection-latency-20260729135024.txt`](evidence/samples/detection-latency-20260729135024.txt) — a real alert firing from real audit-log analysis | generated |
| CA-7 | Continuous Monitoring | — | standing security-posture dashboard | not yet generated — Phase 16 |
| CM-6 | Configuration Settings | `infrastructure/kyverno/policies/`, `kube-bench` | Kyverno PSS enforcement generated; `kube-bench` baseline still Phase 14 | generated (partial) |
| CM-7 | Least Functionality | `infrastructure/kyverno/policies/require-pod-security-restricted.yaml` | [`docs/evidence/samples/kyverno-admission-20260728202845.txt`](evidence/samples/kyverno-admission-20260728202845.txt) — real admission denial of a privileged pod | generated |
| CP-4 | Contingency Plan Testing | `drills/` (five scenarios) | [`docs/evidence/samples/scenario-breadth-20260730021814.txt`](evidence/samples/scenario-breadth-20260730021814.txt) — real, repeatable, re-runnable drills, not one-time snapshots | generated |
| CP-9 | System Backup | `apps/velero.yaml` (hourly Schedule) | [`docs/evidence/samples/ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) — measured RPO 71 records lost | generated |
| CP-10 | System Recovery and Reconstitution | `drills/scenarios/ns-restore.yaml` | [`docs/evidence/samples/ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) — measured RTO 110s | generated |
| IA-2 | Identification and Authentication (Organizational Users) | `infrastructure/keycloak/` OIDC | [`docs/evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt`](evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt) | generated |
| IR-4 | Incident Handling | `drills/lib/open-incident.py`, `infrastructure/glpi/` | [`docs/evidence/samples/incident-response-20260729210627.txt`](evidence/samples/incident-response-20260729210627.txt) — a real GLPI ticket opened automatically, including post-incident-review | generated |
| IR-6 | Incident Reporting | `drills/lib/clocks.py` | [`docs/evidence/samples/incident-response-20260729210627.txt`](evidence/samples/incident-response-20260729210627.txt) — both real computed regulatory deadlines | generated |
| MA-2 | Controlled Maintenance | Argo CD GitOps sync (all changes go through a reviewed, auditable pipeline) | Argo CD sync history | not yet generated |
| MP-6 | Media Sanitization | Velero/MinIO retention policy | — | not yet generated |
| PL-2 | System Security and Privacy Plans | — | toy SSP, generated from this crosswalk (Phase 27, OSCAL) | not yet generated — Phase 27 |
| PM-4 | Plan of Action and Milestones Process | `CHANGELOG.md` "Follow-ups spawned, not yet resolved" section | CHANGELOG.md itself, informally | generated (informal) |
| PS-2 | Position Risk Designation | — | not applicable — solo operator | not applicable |
| RA-5 | Vulnerability Monitoring and Scanning | Trivy Operator | — | not yet generated — Phase 24 |
| SA-11 | Developer Testing and Evaluation | `.github/workflows/build-images.yaml` (build, sign, SBOM, verify) | [`docs/evidence/samples/credential-compromise-20260730044858.txt`](evidence/samples/credential-compromise-20260730044858.txt) — real cosign signature + SBOM attestation verified | generated |
| SC-7 | Boundary Protection | `infrastructure/cilium/` (default-deny across all 8 core namespaces) | [`docs/evidence/samples/cilium-network-segmentation-20260729015300.txt`](evidence/samples/cilium-network-segmentation-20260729015300.txt) | generated |
| SC-12 | Cryptographic Key Establishment and Management | `infrastructure/cert-manager/` offline Root/Intermediate CA | [`docs/evidence/samples/pki-chain-verification-20260729025500.txt`](evidence/samples/pki-chain-verification-20260729025500.txt) | generated |
| SC-13 | Cryptographic Protection | Negotiated TLS version/cipher suite on real leaf certs | — | not yet generated — Phase 26 |
| SC-17 | Public Key Infrastructure Certificates | `infrastructure/cert-manager/` `ca`-type `ClusterIssuer` | [`docs/evidence/samples/pki-chain-verification-20260729025500.txt`](evidence/samples/pki-chain-verification-20260729025500.txt) | generated |
| SI-4 | System Monitoring | `apps/grafana.yaml` Alerting + `apps/tetragon.yaml` eBPF | [`docs/evidence/samples/credential-compromise-20260730044858.txt`](evidence/samples/credential-compromise-20260730044858.txt) — real endpoint-level process monitoring | generated |
| SR-3 | Supply Chain Controls and Processes | `infrastructure/kyverno/policies/verify-image-signatures.yaml` | [`docs/evidence/samples/credential-compromise-20260730044858.txt`](evidence/samples/credential-compromise-20260730044858.txt) | generated |
| SR-4 | Provenance | `.github/workflows/build-images.yaml` (SBOM + Rekor transparency-log entry) | [`docs/evidence/samples/credential-compromise-20260730044858.txt`](evidence/samples/credential-compromise-20260730044858.txt) | generated |

## Reading this table

- Every `generated` row's evidence is also indexed under `docs/evidence/by-control/nist80053/<id>/`
  — see `docs/evidence/manifest.yaml` and `docs/evidence/collect.py`.
- Rows here reuse the *exact same* evidence files as the DORA/NIS2/ISO matrix where the same
  underlying platform mechanism satisfies both — no separate proof was built to pad out this
  table. Where a genuinely new artifact was needed (host compliance status, vulnerability
  scanning, TLS negotiation detail), it's marked `not yet generated` with the phase that produces
  it, same discipline as `docs/03-control-matrix.md`.
- This is a representative subset of applicable families (AC, AT, AU, CA, CM, CP, IA, IR, MA, MP,
  PL, PM, RA, SA, SC, SI, SR), not exhaustive control-by-control coverage within each family.
