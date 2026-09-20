# dora-blueprint

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
| 12 | Supply chain — apko/cosign image signing, `verifyImages`, generated Register of Information | done |
| 13 | Endpoint runtime security — Tetragon + `credential-compromise` scenario | done |
| 14 | Remaining scenarios, kube-bench, evidence report generator | not started |
| 15 | README polish, asciinema, screenshots | not started |
| 16 | Security operations — vulnerability scanning/tracking, continuous monitoring, endpoint/config baseline compliance, living asset inventory | not started |
| 17 | Metrics & infrastructure observability — Prometheus/kube-state-metrics/node-exporter, real resource dashboards | not started |
| 18 | Secrets lifecycle & certificate management — expiry monitoring for the CA chain and leaf certs, secret-age tracking | not started |
| 19 | Chaos engineering breadth + DR tier — scenario 4 (control-plane/etcd loss), cross-cluster restore, Litmus decision | not started |
| 20 | Evidence integrity — write-once/tamper-evident storage for drill records and evidence samples | not started |
| 21 | Evidence tagging & crosswalk infrastructure — multi-framework manifest, generated per-control evidence folders | done |
| 22 | NIST SP 800-53 crosswalk (representative subset, PE excluded — cloud-provider assumption) | done |
| 23 | Host/config compliance scanning — real SELinux/AppArmor/FIPS status across all hosts, honestly reported | done (appserv; Talos nodes documented as architectural fact — no shell exists to query) |
| 24 | Vulnerability management — Trivy Operator, first-detected-date tracking, CISA KEV cross-reference | not started |
| 25 | ATT&CK detection mapping — both real detection rules tagged with the technique they observe | done |
| 26 | Cryptography evidence, expanded — real negotiated TLS version/cipher suite, SOPS/at-rest encryption evidence | not started |
| 27 | OSCAL machine-readable export — real OSCAL JSON generated from the evidence manifest | not started |
| 28 | Real Wazuh deployment (manager + indexer) — a genuine second HIDS/SIEM layer; a leftover, disabled Wazuh agent already sits on appserv from an earlier attempt | not started |

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
- **Phases 17–20 — deeper security & observability**, added at the repo owner's direct request.
  Real gaps this repo's own build surfaced, not generic filler: **17** (metrics/infra
  observability — every dashboard here today is log-based, there's no real CPU/memory/restart
  metrics story at all); **18** (secrets/certificate lifecycle — Phase 7's real CA chain has no
  expiry monitoring); **19** (chaos breadth + the never-built `dr` tier + a real Litmus decision);
  **20** (evidence integrity — closes the write-once/tamper-evidence gap `docs/04-limitations.md`
  already flags). See `BUILD-SPEC.md` §12 for the full scope breakdown on each. Not started.
- **Phases 21/22/25 — multi-framework evidence, NIST 800-53, ATT&CK**, added and built at the
  repo owner's direct request, scoped explicitly as a *reference-architecture capability*
  build — demonstrating the machinery real compliance/detection work needs, not running live
  SOC/ConMon/POA&M operations. `docs/evidence/manifest.yaml` + `collect.py` tag every real
  evidence artifact against five frameworks at once (`dora`/`nis2`/`iso27001`/`nist80053`/
  `attack`) and generate real per-control folders — one artifact lands in several folders where
  it genuinely satisfies several controls, not duplicated by hand. `docs/06-nist-800-53-crosswalk.md`
  reuses that same evidence rather than re-proving anything (PE excluded — cloud-provider
  assumption, no physical controls in scope; PS mostly not-applicable — solo-built, not
  staffed; documentation assumes three operators purely so role-separation controls can be
  described honestly). `docs/07-attack-mapping.md` ties both real detection rules to the ATT&CK
  technique they actually observe, as real Grafana labels on the rules themselves. Done.
- **Phases 23/24/26/27 — host compliance, vuln management, crypto evidence, OSCAL** — the
  remaining pieces of that same push, not yet built. **23** was seeded by a real finding:
  `appserv` has no SELinux at all (Ubuntu uses AppArmor; Talos has no traditional LSM story
  either) — the point isn't to fake compliance, it's to pull and honestly report real host
  security posture, including "not applicable" as a legitimate result. **24** is Trivy Operator
  plus a real CISA KEV cross-reference, not just a CVE count. **27** is the real answer to "can we
  get a machine-readable GPO-style export" — OSCAL is the modern, NIST-native machine-readable
  format for exactly this, generated from the same manifest as Phase 21 rather than hand-written.
- **Phase 28 — real Wazuh deployment.** Investigating a leftover, disabled `filebeat` install on
  appserv (found while cleaning up an unrelated resource-hogging Elastic Agent process) turned up
  that it was actually configured as a Wazuh agent's filebeat module, pointed at a Wazuh indexer
  that no longer exists. Decided with the repo owner: appserv's real host logs
  (`bootstrap/host-log-shipper/`) ship into the existing Loki stack now; a real Wazuh
  manager+indexer, and reviving this agent for real, is its own later phase — a genuine second
  HIDS/SIEM layer (file-integrity monitoring, SCA/CIS compliance checks, vulnerability detection),
  not a replacement for Loki/Grafana.
- **Not yet scheduled to a phase:** a jumphost/bastion replacing today's ad-hoc
  `kubectl port-forward` access pattern with a real network-level Ingress; a real standing
  webhook receiver for alerts independent of drill runs.

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
