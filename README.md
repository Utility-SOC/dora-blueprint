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
make lab-core                       # Talos + Cilium + Argo CD + everything ns-restore needs
make drill SCENARIO=ns-restore      # inject a fault, recover, classify, ticket — all measured
```

| Tier | Command | Deploys | Contents |
|---|---|---|---|
| `core` | `make lab-core` | `apps/core/` | Talos, Cilium, cert-manager, Kyverno, storage, the observability pipeline (Alloy/Loki/Grafana), the canary, Argo Workflows, Velero + MinIO, GLPI — everything `make drill SCENARIO=ns-restore` itself needs to fully succeed |
| `full` | `make lab-full` | `apps/core/` + `apps/full/` | + IAM (Keycloak/Postgres/OpenLDAP/LAM), Tetragon (needed for the `credential-compromise` scenario's detection path), Trivy Operator + findings exporter |
| `dr` | `make lab-dr` | — | Not implemented — needs a genuine second cluster for cross-cluster restore drills, not just another Application set on this one cluster. `full` is real; this isn't yet (build-spec Phase 19) |

`TIER` only controls which Argo CD Applications get synced (`apps/core/` always; `apps/full/`
in addition when `TIER=full`) — the underlying Talos cluster's own memory footprint
(`bootstrap/install.sh`'s `--memory-controlplanes`/`--memory-workers` flags) is fixed regardless
of tier, so `full` runs more workloads on the same cluster capacity rather than a bigger one.
No RAM figures are stated here since none have been measured against this split — see
`bootstrap/install.sh` for the exact real flags if you need to size a host.

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

## DORA, article by article

<!-- dora-coverage:start (generated by docs/compliance/dora_readme.py; edit the CSV, not this block) -->

Every article of DORA (Regulation (EU) 2022/2554), with how this lab addresses it technically. The full sheet, with 108 rows including paragraph-level detail and the Level 2 technical standards, is [`docs/compliance/dora-coverage.csv`](docs/compliance/dora-coverage.csv) (it renders as a table on GitHub and opens in any spreadsheet tool).

Status words: **Implemented** (a mechanism exists *and* produced evidence), **Partial**, **Not met**, **Not applicable** (addressed to someone else), **Context**. "Implemented" never means a tenant is compliant. See [`docs/04-limitations.md`](docs/04-limitations.md).

Article-level count: Context 5, Not applicable 34, Not met 7, Out of scope 2, Partial 16.

| Art. | Title | Status | How it is addressed technically | Implemented by | Gaps / next task |
|---|---|---|---|---|---|
| 1–3 | Subject matter, scope, definitions | Context | Framing in [`docs/00-scope.md`](docs/00-scope.md): the notional tenant is a payment institution, which Art. 2 brings in scope | | |
| 4 | Proportionality principle | Partial | Proportionality reasoning for a small payment institution written down; not quantified. | [`docs/00-scope.md`](docs/00-scope.md) | T32 |
| 5 | Governance and organisation | Not met | Management-body accountability is people and process. A three-operator RACI is assumed for documentation only. (1 paragraph row in the sheet) | [`BUILD-SPEC.md`](BUILD-SPEC.md) | G5; T32, F03 |
| 6 | ICT risk management framework | Partial | The platform, its docs and its generated evidence form the technical half of a framework; risk register and strategy missing. (4 paragraph rows in the sheet) | [`docs/03-control-matrix.md`](docs/03-control-matrix.md), [`docs/05-shared-responsibility.md`](docs/05-shared-responsibility.md) | G14; T15, T32 |
| 7 | ICT systems, protocols and tools | Partial | Immutable, API-driven OS (Talos); everything pinned and GitOps-reconciled. No capacity/performance metrics yet. | [`platform/talos/`](platform/talos/), [`apps/`](apps/) +1 | Phase 17 |
| 8 | Identification | Partial | Generated inventory of every chart and image; heuristic critical-asset labels; no yearly review. (1 paragraph row in the sheet) | [`images/generate-roi.py`](images/generate-roi.py), [`infrastructure/trivy-operator/`](infrastructure/trivy-operator/) | T30, Phase 16 |
| 9 | Protection and prevention | Partial | Admission control, default-deny networking, internal PKI, SSO with RBAC, signed images, encryption at rest. (7 paragraph rows in the sheet) | [`infrastructure/kyverno/`](infrastructure/kyverno/), [`infrastructure/cilium/`](infrastructure/cilium/) +2 | G7, G9; T02a, T14 |
| 10 | Detection | Partial | Two real alert rules over two layers (API audit log, Tetragon eBPF); measured detection latency. No paging. (2 paragraph rows in the sheet) | [`apps/core/grafana.yaml`](apps/core/grafana.yaml), [`apps/full/tetragon.yaml`](apps/full/tetragon.yaml) | G8; T13 |
| 11 | Response and recovery | Partial | Five measured drills with runbooks; no BCP, BIA or audit of plans. (4 paragraph rows in the sheet) | [`drills/`](drills/), [`docs/runbooks/`](docs/runbooks/) | G4, G14; T11, T15, T32 |
| 12 | Backup policies, restoration and recovery | Partial | Velero + MinIO, measured RTO and exact RPO, hash-chain integrity check. Same-cluster restore; verdict ignores targets. (5 paragraph rows in the sheet) | [`infrastructure/velero/`](infrastructure/velero/), [`canary/`](canary/) +1 | G1, G3, G10; T09, Phase 19 |
| 13 | Learning and evolving | Partial | Threat/vulnerability intake via Trivy + CISA KEV; post-incident review section on every ticket (boilerplate). | [`infrastructure/trivy-operator/`](infrastructure/trivy-operator/), [`drills/lib/open-incident.py`](drills/lib/open-incident.py) | G24; T32 |
| 14 | Communication | Not met | No crisis communication plan. |  | T32 |
| 15 | Further harmonisation of ICT risk management tools, methods, processes and policies | Context | Mandate for the RTS on the ICT risk management framework (see the Delegated Regulation (EU) 2024/1774 row). |  |  |
| 16 | Simplified ICT risk management framework | Not applicable | The notional tenant is modelled as a fully authorised payment institution, not eligible for the simplified framework. | [`docs/00-scope.md`](docs/00-scope.md) |  |
| 17 | ICT-related incident management process | Partial | Every drill opens a GLPI incident with classification, deadlines and links to evidence. (3 paragraph rows in the sheet) | [`drills/lib/open-incident.py`](drills/lib/open-incident.py), [`infrastructure/glpi/`](infrastructure/glpi/) | T32 |
| 18 | Classification of ICT-related incidents and cyber threats | Partial | classify.py implements a simplified version of the criteria; two inputs measured, the rest labelled synthetic. (1 paragraph row in the sheet) | [`drills/lib/classify.py`](drills/lib/classify.py), [`drills/lib/classification-profiles.json`](drills/lib/classification-profiles.json) | G11 |
| 19 | Reporting of major incidents; voluntary notification of significant cyber threats | Partial | Initial notification deadline computed, NIS2 clock shown beside it. Nothing is submitted to any authority. (3 paragraph rows in the sheet) | [`drills/lib/clocks.py`](drills/lib/clocks.py) | G12; T10, T29 |
| 20 | Harmonisation of reporting content and templates | Not met | Report drafts in the official template structure are not generated. |  | T29 |
| 21 | Centralisation of reporting of major ICT-related incidents | Out of scope | EU-level hub design is for the ESAs. |  |  |
| 22 | Supervisory feedback | Out of scope | Regulator-side. |  |  |
| 23 | Operational or security payment-related incidents | Partial | Applies to the notional payment institution; handled by the same classification and clock pipeline. No payment-specific fields. | [`drills/lib/`](drills/lib/) | T29 |
| 24 | General requirements for digital operational resilience testing | Partial | Five scenarios wired to workflow, runbook, profile and schema. Not scheduled; tester is not independent. (2 paragraph rows in the sheet) | [`drills/scenarios/`](drills/scenarios/), [`drills/templates/`](drills/templates/) | G4, G5; T11 |
| 25 | Testing of ICT tools and systems | Partial | Vulnerability scans, network security test, scenario and end-to-end tests. No performance, penetration or source-code review testing. | [`infrastructure/trivy-operator/`](infrastructure/trivy-operator/), [`drills/`](drills/) | G22; F08 |
| 26 | Advanced testing based on TLPT | Not met | Deliberately not claimed; needs independent testers on live production systems. | [`docs/04-limitations.md`](docs/04-limitations.md) | G6 |
| 27 | Requirements for testers carrying out TLPT | Not applicable | The lab does not engage TLPT testers. |  |  |
| 28 | General principles (ICT third-party risk) | Partial | Generated Register of Information from the real inventory; signed images with SBOM for the repo's own image. Contract fields synthetic. (3 paragraph rows in the sheet) | [`images/generate-roi.py`](images/generate-roi.py), [`.github/workflows/build-images.yaml`](.github/workflows/build-images.yaml) +1 | G13; T30, T31 |
| 29 | Preliminary assessment of ICT concentration risk at entity level | Not met | A generated concentration analysis over the register is planned. |  | T30 |
| 30 | Key contractual provisions | Not met | No vendor contracts (all self-run open source); checklist template planned. |  | G13; T31 |
| 31–44 | Oversight of critical ICT third-party providers | Not applicable | Between the ESAs and the providers; a firm still owes Art. 28 due diligence on any CTPP it uses | | |
| 45 | Information-sharing arrangements on cyber threat information and intelligence | Not met | No sharing arrangement. A STIX 2.1 export of the lab's detections is planned as a teaching example. |  | T33 |
| 46–56 | Competent authorities, cooperation, penalties | Not applicable | Addressed to authorities (in Ireland, the Central Bank of Ireland) | | |
| 57–64 | Delegated acts, review, amendments, entry into force | Context | Procedural; DORA applies from 17 January 2025 | | |

**Level 2 technical standards** (numbers to be verified on EUR-Lex before relying on them):

| Instrument | Under Art. | Subject | Status |
|---|---|---|---|
| Commission Delegated Regulation (EU) 2024/1774 | 15, 16 | RTS on the ICT risk management framework and simplified framework | Partial |
| Commission Delegated Regulation (EU) 2024/1772 | 18 | RTS on classification criteria and materiality thresholds | Partial |
| Commission Delegated Regulation (EU) 2024/1773 | 28(10) | RTS on the policy for ICT services supporting critical or important functions | Not met |
| Commission Implementing Regulation (EU) 2024/2956 | 28(9) | ITS on standard templates for the register of information | Not met |
| Commission Delegated Regulation (EU) 2025/301 | 20 | RTS on content and time limits of incident reports | Partial |
| Commission Implementing Regulation (EU) 2025/302 | 20 | ITS on standard forms and templates for incident reporting | Not met |
| Commission Delegated Regulation on TLPT (number to verify) | 26(11) | RTS specifying TLPT criteria and methodology | Not met |
| RTS on subcontracting of ICT services (Art. 30(5); status to verify) | 30(5) | Conditions for subcontracting ICT services supporting critical or important functions | Not met |

Gap IDs (G1–G24) refer to the gaps register in `docs/compliance/gaps.md` (PR #3); task IDs refer to [`docs/roadmap/`](docs/roadmap/README.md).

<!-- dora-coverage:end -->

## Status

Built phase-by-phase per [`BUILD-SPEC.md`](BUILD-SPEC.md) §12, breadth-last. Phase 3 is the
milestone the build spec names as the point the project's thesis is proven — everything after
is expansion, not proof of concept.

**Phases 10, 11, 12, and 13 are all done.** Phase 12 (supply chain) was deliberately skipped ahead
of and picked up later.

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
| 14 | Remaining scenarios, kube-bench, evidence report generator | partial (`make evidence` done; kube-bench and the three remaining scenarios need a live cluster, still not started) |
| 15 | README polish, asciinema, screenshots | not started |
| 16 | Security operations — vulnerability scanning/tracking, continuous monitoring, endpoint/config baseline compliance, living asset inventory | not started |
| 17 | Metrics & infrastructure observability — Prometheus/kube-state-metrics/node-exporter, real resource dashboards | not started |
| 18 | Secrets lifecycle & certificate management — expiry monitoring for the CA chain and leaf certs, secret-age tracking | not started |
| 19 | Chaos engineering breadth + DR tier — scenario 4 (control-plane/etcd loss), cross-cluster restore, Litmus decision | not started |
| 20 | Evidence integrity — write-once/tamper-evident storage for drill records and evidence samples | done (hash chain + keyless-signed chain head; MinIO object-lock remains a possible second mechanism, not built) |
| 21 | Evidence tagging & crosswalk infrastructure — multi-framework manifest, generated per-control evidence folders | done |
| 22 | NIST SP 800-53 crosswalk (representative subset, PE excluded — cloud-provider assumption) | done |
| 23 | Host/config compliance scanning — real SELinux/AppArmor/FIPS status across all hosts, honestly reported | done (appserv; Talos nodes documented as architectural fact — no shell exists to query) |
| 24 | Vulnerability management — Trivy Operator, first-detected-date tracking, CISA KEV cross-reference | done |
| 25 | ATT&CK detection mapping — both real detection rules tagged with the technique they observe | done |
| 26 | Cryptography evidence, expanded — real negotiated TLS version/cipher suite, SOPS/at-rest encryption evidence | not started |
| 27 | OSCAL machine-readable export — real OSCAL JSON generated from the evidence manifest | done |
| 28 | Real Wazuh deployment (manager + indexer) — a genuine second HIDS/SIEM layer; a leftover, disabled Wazuh agent already sits on appserv from an earlier attempt | not started |

Full phase-by-phase build notes — real bugs found and fixed by actually running each phase, not
assumed from a clean apply — are in [`CHANGELOG.md`](CHANGELOG.md).

## Roadmap: what's still ahead

- **Scenario 4 — control-plane/etcd loss (deferred, no target phase yet).** This lab has exactly
  one Talos control-plane node — no etcd quorum to lose gracefully, so this fault takes down the
  *entire* platform (Argo CD, Grafana, GLPI, Keycloak, every namespace), not just the canary
  tenant, until fully rebuilt. Deliberately not folded into Phase 10 alongside the other,
  much lower-blast-radius scenarios; will get its own dedicated pass.
- **Phase 14 — Remaining scenarios, kube-bench, evidence report generator (partial).**
  `make evidence` is done — `docs/evidence/report.py`/`oscal.py` generate a consolidated
  Markdown report and a real OSCAL JSON export (Phase 27) from `manifest.yaml`;
  `docs/03-control-matrix.md` stays the authoritative, hand-maintained index. `kube-bench` and
  the three remaining drill scenarios (DNS failure, certificate expiry, clock skew) still need a
  live cluster to build and verify against — not started.
- **Phase 16 — Security operations.** Everything up through Phase 13 proves one narrow thing per
  drill or admission check; nothing yet stands watch continuously, independent of a drill
  happening to run. Vulnerability scanning and tracking (severity, first-detected date, age
  against a stated SLA window, CISA KEV cross-reference) is done — built as Phase 24, see
  `infrastructure/trivy-operator/` and the "Vulnerability management" Grafana dashboard. Still
  open: standing security-monitoring alerts independent of drill triggers, `kube-bench` tracked
  over time rather than one-off, and a living asset inventory connecting Phase 12's generated
  Register of Information to GLPI's own asset module. Organized with the breadth of a mature security
  control catalog without naming or branding it after any specific external framework — see
  `BUILD-SPEC.md` §12 for the full scope breakdown. Not started.
- **Phases 17–19 — deeper security & observability**, added at the repo owner's direct request.
  Real gaps this repo's own build surfaced, not generic filler: **17** (metrics/infra
  observability — every dashboard here today is log-based, there's no real CPU/memory/restart
  metrics story at all); **18** (secrets/certificate lifecycle — Phase 7's real CA chain has no
  expiry monitoring); **19** (chaos breadth + the never-built `dr` tier + a real Litmus decision).
  See `BUILD-SPEC.md` §12 for the full scope breakdown on each. Not started.
- **Phase 20 — evidence integrity — done.** Closes the write-once/tamper-evidence gap
  `docs/05-shared-responsibility.md` and `docs/06-operations.md` both flag plainly: today's
  evidence samples were plain git-tracked files, so git history alone was their tamper-evidence
  property. `docs/evidence/chain.py` sha256-chains every file in `docs/evidence/samples/`
  (`make evidence-verify` checks it), and `.github/workflows/evidence-integrity.yaml` signs the
  chain head keylessly in CI (GitHub OIDC -> Fulcio -> Rekor, reusing Phase 12's image-signing
  mechanism for a blob instead of an image) — a real, independently-checkable anchor, not just
  "trust git history." MinIO object-lock remains a possible second, stronger mechanism, not
  built.
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
- **Phases 23/24/27 — host compliance, vuln management, OSCAL — done.** **23** was seeded by a
  real finding: `appserv` has no SELinux at all (Ubuntu uses AppArmor; Talos has no traditional
  LSM story either) — the point isn't to fake compliance, it's to pull and honestly report real
  host security posture, including "not applicable" as a legitimate result. **24** is Trivy
  Operator plus a real CISA KEV cross-reference and first-detected-date/SLA tracking, not just a
  CVE count. **27** is the real answer to "can we get a machine-readable GPO-style export" —
  OSCAL is the modern, NIST-native machine-readable format for exactly this
  (`docs/evidence/oscal.py`, a representative subset of the `assessment-results` model, not a
  verbatim schema implementation), generated from the same manifest as Phase 21 rather than
  hand-written.
- **Phase 26 — cryptography evidence, expanded** — not yet built. Real negotiated TLS
  version/cipher suite and SOPS/at-rest encryption evidence both need a live cluster to capture
  (an actual served-certificate handshake, an actual encrypted secret), unlike 20/27 above which
  were buildable and verifiable without one.
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
