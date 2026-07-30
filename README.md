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

Three more scenarios exist as of Phase 10: `SCENARIO=node-kill` (taints and force-deletes the
canary's own node), `SCENARIO=pvc-corruption-restore` (corrupts the canary's data in place, then
restores from backup), and `SCENARIO=network-partition` (a real, repeatable Cilium enforcement
check — denies and un-denies a live path, proving it both directions). All four feed the same
classification/clocks/GLPI pipeline and the RTO/RPO trend dashboard in Grafana. Sample:
[`docs/evidence/samples/scenario-breadth-20260730021814.txt`](docs/evidence/samples/scenario-breadth-20260730021814.txt).

A fifth scenario exists as of Phase 13: `SCENARIO=credential-compromise` (harvests the canary's
own ServiceAccount token, then spawns a shell — a real `execve` observed by Tetragon's eBPF
instrumentation and caught by a Grafana Alerting rule watching Loki, the same detection pattern
Phase 9 established). Nothing is actually broken by this one — it validates the runtime-detection
path end to end, the way `network-partition` validates the enforcement path. Sample:
[`docs/evidence/samples/credential-compromise-20260730044858.txt`](docs/evidence/samples/credential-compromise-20260730044858.txt)
(detection latency 11s, GLPI ticket #7).

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
| Tetragon | eBPF-based endpoint runtime security — real process-exec visibility feeding the `credential-compromise` drill's detection path |

See [`docs/06-operations.md`](docs/06-operations.md) for day-to-day usage and change procedures.

## Status

Built phase-by-phase per [`BUILD-SPEC.md`](BUILD-SPEC.md) §12, breadth-last. Phase 3 is the
milestone the build spec names as the point the project's thesis is proven — everything after
is expansion, not proof of concept.

**Phases 10, 11, and 13 are all done. Phase 12 (supply chain) was deliberately skipped ahead of
— still unstarted, ready to pick up whenever.**

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
| 10 | Scenario breadth (1, 3, 5) + RTO/RPO trend dashboard (scenario 4 deferred — see below) | done |
| 11 | Incident response — classification, regulatory clocks, GLPI ticket automation | done |
| 12 | Supply chain — apko/cosign image signing, `verifyImages`, generated Register of Information | not started |
| 13 | Endpoint runtime security — Tetragon + `credential-compromise` scenario | done |
| 14 | Remaining scenarios, kube-bench, evidence report generator | not started |
| 15 | README polish, asciinema, screenshots | not started |
| 16 | Security operations — vulnerability scanning/tracking, continuous monitoring, endpoint/config baseline compliance, living asset inventory | not started |

Full phase-by-phase build notes — real bugs found and fixed by actually running each phase, not
assumed from a clean apply — are in [`CHANGELOG.md`](CHANGELOG.md).

## Roadmap: what's still ahead

- **Scenario 4 — control-plane/etcd loss (deferred, no target phase yet).** This lab has exactly
  one Talos control-plane node — no etcd quorum to lose gracefully, so this fault takes down the
  *entire* platform (Argo CD, Grafana, GLPI, Keycloak, every namespace), not just the canary
  tenant, until fully rebuilt. Deliberately not folded into Phase 10 alongside the other,
  much lower-blast-radius scenarios; will get its own dedicated pass.
- **Phase 12 — Supply chain.** Build-time image signing (apko + cosign keyless signing),
  `verifyImages` admission enforcement, and a generated Register of Information / SBOMs for
  DORA Art. 28–30. Not started; the likely target is repackaging `canary/writer.py` as a signed
  apko-built image.
- **Phase 14 — Remaining scenarios, kube-bench, evidence report generator.** `make evidence` is
  currently a stub; today, `docs/03-control-matrix.md` is the hand-maintained index into
  `docs/evidence/samples/` — see [`docs/06-operations.md`](docs/06-operations.md) §4.
- **Phase 16 — Security operations.** Everything up through Phase 13 proves one narrow thing per
  drill or admission check; nothing yet stands watch continuously, independent of a drill
  happening to run. Phase 16 closes that gap: real vulnerability scanning and tracking (severity,
  first-detected date, age against a stated SLA window — Trivy Operator is the leading candidate;
  `infrastructure/trivy-operator/` is currently an empty placeholder, not a running scanner),
  standing security-monitoring alerts independent of drill triggers, `kube-bench` tracked over
  time rather than one-off, and a living asset inventory connecting Phase 12's generated Register
  of Information to GLPI's own asset module. Organized with the breadth of a mature security
  control catalog without naming or branding it after any specific external framework — see
  `BUILD-SPEC.md` §12 for the full scope breakdown. Not started.
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
