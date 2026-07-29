# elastic-dora-blueprint

A GitOps Kubernetes reference architecture demonstrating DORA, NIS2, and ISO 27001 controls,
with automated recovery drills that emit measured evidence. Framed as a security control plane
/ landing zone that a regulated tenant application is onboarded onto — see
[`docs/00-scope.md`](docs/00-scope.md) §0.1 for the platform-vs-tenant distinction.

> Most compliance repos assert their recovery objectives. This one measures them, on a
> schedule, and stores the results as tamper-evident evidence mapped to specific regulatory
> articles.

**What this is not:** a compliance product, a certification, or a claim that any organisation
running it is compliant. ISO 27001 certifies a management system, not a toolchain. DORA and
NIS2 apply to regulated entities, not repositories. See [`docs/00-scope.md`](docs/00-scope.md)
and [`docs/04-limitations.md`](docs/04-limitations.md).

## Quick start

```bash
make lab-core                       # Talos + Cilium + Argo CD, ~10GB RAM
make drill SCENARIO=ns-restore      # inject a fault, recover, classify, ticket — all measured
```

| Tier | Command | RAM | Contents |
|---|---|---|---|
| `core` | `make lab-core` | ~10 GB | Talos, Cilium, cert-manager, Kyverno, Argo CD, Trivy, lightweight log sink |
| `full` | `make lab-full` | ~28 GB | + Elastic/Fleet/eBPF agent, Velero + MinIO, Argo Workflows, Litmus |
| `dr` | `make lab-dr` | ~40 GB | + second cluster for cross-cluster restore drills |

`make drill` deletes the canary namespace, restores it from a real Velero backup into a
freshly-named namespace, and prints a *measured* RTO and RPO — not asserted numbers. Sample:
[`docs/evidence/samples/ns-restore-20260728152755.json`](docs/evidence/samples/ns-restore-20260728152755.json)
(RTO 110s, RPO 71 records, hash-chain `integrity_check: pass`).

## What's running

| Component | Role |
|---|---|
| Talos + Cilium + Argo CD | The cluster itself, GitOps-managed end to end (`bootstrap/install.sh` is the one manual-apply exception) |
| Kyverno | Pod Security Standards `restricted`, enforced cluster-wide from the start |
| cert-manager | Offline Root CA → Intermediate CA → real leaf certs for every internal service |
| Keycloak + OpenLDAP | OIDC SSO and real group-based RBAC for Argo CD and Grafana |
| Grafana + Loki + Alloy | Log pipeline plus a real Alerting rule that produces `t_detect` |
| Velero + MinIO | Backup/restore — what the `ns-restore` drill actually measures |
| Argo Workflows | Runs drill scenarios as real Workflows, not shell scripts on a laptop |
| GLPI + MariaDB | Self-hosted ITSM — drills open real tickets with computed regulatory deadlines |

See [`docs/06-operations.md`](docs/06-operations.md) for day-to-day usage and change procedures.

## Status

Built phase-by-phase per [`BUILD-SPEC.md`](BUILD-SPEC.md) §12, breadth-last. Phase 3 is the
milestone the build spec names as the point the project's thesis is proven — everything after
is expansion, not proof of concept.

**Phase 11 (Incident response) is done. Next phase not yet chosen — Phase 10 (scenario breadth)
and Phase 12 (supply chain) are both unstarted and ready to pick up.**

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Scope docs, control-matrix skeleton, repo layout | done |
| 1 | Talos + Cilium + Argo CD + SOPS, everything pinned | done |
| 2 | Canary workload + drill record schema + emitter + log sink | done |
| 3 | Velero + MinIO + `ns-restore` scenario (**thesis proven**) | done |
| 4 | Kyverno PSS `restricted` enforcement + API audit logging | done |
| 5 | Platform/landing-zone generalization | done |
| 6 | Network segmentation — Cilium default-deny across all 8 core namespaces | done |
| 7 | PKI foundation — offline Root/Intermediate CA, real leaf certs | done |
| 8 | IAM — Keycloak + OpenLDAP, OIDC SSO, real RBAC | done |
| 9 | Detection — real Grafana Alerting rule, real `t_detect` | done |
| 10 | Scenario breadth (1, 3, 4, 5) + RTO/RPO trend dashboard | not started |
| 11 | Incident response — classification, regulatory clocks, GLPI ticket automation | done |
| 12 | Supply chain — apko/cosign image signing, `verifyImages`, generated Register of Information | not started |
| 13 | Endpoint runtime security | not started |
| 14 | Remaining scenarios, kube-bench, evidence report generator | not started |
| 15 | README polish, asciinema, screenshots | not started |

Full phase-by-phase build notes — real bugs found and fixed by actually running each phase, not
assumed from a clean apply — are in [`CHANGELOG.md`](CHANGELOG.md).

## Roadmap: what's still ahead

- **Phase 10 — Scenario breadth.** Only `ns-restore` (namespace delete → restore) exists today.
  Scenarios 1 (node kill), 3 (PVC corruption → snapshot restore), 4 (control-plane/etcd loss),
  and 5 (network partition) are designed in `BUILD-SPEC.md` §6.3 but not built, plus an RTO/RPO
  trend chart across multiple runs.
- **Phase 12 — Supply chain.** Build-time image signing (apko + cosign keyless signing),
  `verifyImages` admission enforcement, and a generated Register of Information / SBOMs for
  DORA Art. 28–30. Not started; the likely target is repackaging `canary/writer.py` as a signed
  apko-built image.
- **Phase 13 — Endpoint runtime security.** Elastic Defend or Tetragon (open question), plus
  scenario 8 (credential compromise → shell spawn → runtime detection). Not started.
- **Phase 14 — Remaining scenarios, kube-bench, evidence report generator.** `make evidence` is
  currently a stub; today, `docs/03-control-matrix.md` is the hand-maintained index into
  `docs/evidence/samples/` — see [`docs/06-operations.md`](docs/06-operations.md) §4.
- **Not yet scheduled to a phase:** a jumphost/bastion replacing today's ad-hoc
  `kubectl port-forward` access pattern with a real network-level Ingress; evidence
  write-once/tamper-evidence guarantees (build-spec P7); a real standing webhook receiver for
  alerts independent of drill runs.

## Docs

- [`docs/00-scope.md`](docs/00-scope.md) — platform/tenant framing, lex specialis reasoning, per-tenant DORA Art. 16 analysis
- [`docs/03-control-matrix.md`](docs/03-control-matrix.md) — control traceability, the front-door artifact
- [`docs/04-limitations.md`](docs/04-limitations.md) — what this lab cannot demonstrate, and why
- [`docs/05-shared-responsibility.md`](docs/05-shared-responsibility.md) — control-by-control platform-vs-tenant breakdown
- [`docs/06-operations.md`](docs/06-operations.md) — usage, change procedures, ticketing, and where evidence gets parsed (today vs. planned)
- [`CHANGELOG.md`](CHANGELOG.md) — phase-by-phase build notes and real bugs found along the way
- [`BUILD-SPEC.md`](BUILD-SPEC.md) — the full build specification this repo follows

## Observability

Pluggable by design, not by vendor: `core` profile targets a lightweight sink; `full` profile
adds Elastic/Fleet/eBPF. See `infrastructure/observability/`.
