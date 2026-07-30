# Resilience Lab — Build Specification

A GitOps Kubernetes reference architecture demonstrating DORA, NIS2, and ISO 27001 controls, with **automated recovery drills that emit measured evidence**.

> **This document is the source of truth for the build.** It is written to be handed to an agentic coding assistant. Read the whole thing before writing any code. Where this document conflicts with your priors about "how these tools are normally used," follow this document — the deviations are deliberate and are explained.

---

## 0. What this project is, and what it is not

**It is:** a runnable lab that produces *machine-generated, timestamped evidence* that recovery objectives are met, control policies are enforced, and incidents are detected, classified, and routed within regulatory clocks.

**It is not:** a compliance product, a certification, or a claim that any organisation running it is compliant. ISO 27001 certifies a management system, not a toolchain. DORA and NIS2 apply to entities, not repos. The README must say this plainly.

### The one-sentence thesis

> Most compliance repos assert their recovery objectives. This one measures them, on a schedule, and stores the results as tamper-evident evidence mapped to specific regulatory articles.

Every design decision should be traceable back to that sentence. If a feature does not either (a) enforce a control, (b) produce evidence, or (c) make the lab deployable by a stranger, it is out of scope for v1.

### Success criteria

1. A stranger with 32 GB RAM runs two commands and has a working cluster.
2. A third command (`make drill SCENARIO=...`) injects a fault, recovers, and prints a measured RTO/RPO.
3. `docs/` contains a control traceability matrix whose evidence column points at real generated artifacts, not at YAML.
4. Nothing in the repo claims a capability it does not implement.

---

## 1. Non-negotiable principles

These are the things that make the project read as good judgement rather than tool assembly. Violating any of them is a build failure, not a style preference.

| # | Principle | Why |
|---|---|---|
| P1 | **No claim without an implementation.** Every capability asserted in prose must be traceable to a file. | The most common failure mode of this genre. |
| P2 | **Every exception is explicit, scoped, and reasoned.** Privileged workloads get a committed `PolicyException` plus a written risk acceptance naming the accepter and the compensating control. | Documented exceptions *are* the demonstration of judgement. Silent ones are the opposite. |
| P3 | **Everything is pinned.** Chart versions, image digests, git SHAs. No `HEAD`, no `stable`, no `:latest`, anywhere. | "Immutable infrastructure" is otherwise a lie. |
| P4 | **No manual `kubectl apply` for workloads.** Bootstrap is the only exception and must be scripted, idempotent, and re-runnable. | Change control. |
| P5 | **No plaintext secrets, and no out-of-band manual secret creation.** SOPS + age, encrypted material committed to Git. | Reproducibility *and* secret hygiene are not in tension if you use the right tool. |
| P6 | **Objectives are measured, never asserted.** RTO/RPO come from probes, not from a YAML field a human typed. | This is the whole project. |
| P7 | **Evidence is write-once.** ILM + write-only ingest role + snapshots to object-locked storage. | Logs an admin can silently delete are not evidence. |
| P8 | **Scope limitations are stated, not hidden.** | See §11. |

---

## 2. Corrections to prior art

An earlier draft of this architecture (LLM-generated, not to be reused) contained the following errors. They are listed so they are not reintroduced.

- **Cilium cannot be an Argo CD sync-wave.** Argo CD needs a working CNI to schedule at all. The CNI comes up with the cluster; Argo adopts it afterwards.
- **`/var/lib/docker/containers` does not exist** on k3s or Talos. Both use containerd. Use `/var/log/pods` and the containerd socket path for the chosen distro.
- **A privileged eBPF agent violates the baseline policy it ships alongside** unless an explicit exception exists. Additionally, `kube-system` is excluded from the Kyverno webhook by default, so the policy silently would not have evaluated it at all. Do not deploy security tooling into a namespace where your own policies are disabled.
- **Hand-rolled `privileged: false` pattern matching misses `initContainers` and `ephemeralContainers`** and is trivially bypassed. Use Kyverno's `validate.podSecurity` against the Pod Security Standards profiles.
- **`spec.validationFailureAction` is deprecated** in current Kyverno in favour of per-rule `failureAction`.
- **cert-manager CRDs exceed the client-side apply annotation size limit.** Requires `ServerSideApply=true` in the Argo CD sync options.
- **cert-manager does not provide mTLS.** It issues certificates. Workload-to-workload encryption requires a mesh or Cilium WireGuard/IPsec transparent encryption. Pick one and say which.
- **Installing Cilium does not create network policy.** Policies are the control; the CNI is only the mechanism. Default-deny plus explicit allows must exist as files.
- **API server audit logging is off by default** in k3s and must be explicitly configured. It is the single highest-value log source for all three frameworks.
- **`project: default` in Argo CD means no guardrails.** Argo running effectively cluster-admin with no AppProject scoping is the most likely real compromise path in a design like this.

---

## 3. Regulatory scope (decide this first, it shapes everything)

Write `docs/00-scope.md` before writing code.

- **Notional entity:** a small-to-medium EU payment institution. Pick this explicitly; proportionality is a real feature of both regimes. As of Phase 5, this entity is modeled as one example tenant onboarded onto a shared platform/landing-zone, not the sole subject of the repo — see `docs/00-scope.md` §0.6 for the full platform-vs-tenant distinction.
- **DORA is *lex specialis* to NIS2** for financial entities (NIS2 Art. 4) — DORA's ICT requirements displace the NIS2 equivalents rather than stacking. State this. It is a strong signal that the primary sources were read.
- Note DORA Art. 16's simplified framework for smaller entities and state whether the notional entity falls under it.
- ISO 27001: the standard is Clauses 4–10 (the ISMS). Annex A is a control menu. The repo implements *some Annex A controls*; it does not implement an ISMS. The Statement of Applicability makes this distinction visible.

### Article map to keep visible during the build

| Area | DORA | NIS2 | ISO 27001 Annex A |
|---|---|---|---|
| ICT risk management framework | Art. 5–6 | 21(2)(a) | A.5.1–A.5.8 |
| Protection & prevention | Art. 9 | 21(2)(e),(i) | A.8.x |
| Detection | Art. 10 | 21(2)(b) | A.8.16 |
| Response & recovery | Art. 11–12 | 21(2)(c) | A.5.29, A.8.13, A.8.14 |
| Learning & evolving | Art. 13 | — | A.5.27 |
| Incident classification | Art. 18 + RTS | 23 | A.5.25 |
| Incident reporting clocks | Art. 19 | 23 | A.5.26 |
| Resilience testing | Art. 24–27 | 21(2)(f) | A.5.30, A.8.29 |
| Third-party / supply chain | Art. 28–30 | 21(2)(d) | A.5.19–A.5.22, A.8.8 |
| Clock synchronisation | (enabling) | — | A.8.17 |

### Reporting clocks — implement both, show the divergence

- **DORA Art. 19:** initial notification within **4h of classification** as major, and no later than **24h from detection**; intermediate at **72h**; final within **1 month**.
- **NIS2 Art. 23:** early warning **24h from awareness**; incident notification **72h**; final report **1 month**.

Compute both from the same event timeline. The divergence between "classification" and "awareness" as clock-start events is the interesting part and should be surfaced in the drill output.

---

## 4. Platform decision

**Primary: Talos Linux.** Chosen because node hardening becomes GitOps-managed configuration rather than bespoke automation, and because it is API-driven, which is what makes control-plane destruction drills genuinely testable rather than simulated.

Talos machine config covers, as declarative fields: NTP servers, KSPP sysctls, kernel module allowlists, disk encryption (LUKS2, TPM-sealed), Secure Boot, and **API server audit policy**. There is no shell and no SSH, which removes an entire class of drift.

`talosctl cluster create` gives a multi-node cluster in Docker in roughly 90 seconds — this directly serves the deployability requirement.

**Secondary: `bare-metal/` Ansible role** producing CIS-hardened Ubuntu + k3s. Keep this as an alternative path. It demonstrates transferable skills for shops that run conventional distros, and gives the project something honest to say about portability. It is *not* required for v1 — build it after the core loop works.

### Node config must include

- chrony/NTP pinned to named sources, `makestep` bounded — and a `docs/` note explaining that **every RTO/RPO measurement and every cross-source log correlation in this project is only admissible because of this** (ISO A.8.17).
- API server audit policy: `RequestResponse` for secrets and RBAC changes, `Metadata` for the rest. Shipped to the log sink.
- etcd encryption at rest.
- KSPP sysctls, module allowlist, Secure Boot where the host supports it.

---

## 5. Repository layout

```
resilience-lab/
├── README.md                     # tiering table + asciinema + screenshots up top
├── Makefile                      # lab-core, lab-full, lab-dr, drill, evidence, images
├── docs/
│   ├── 00-scope.md               # notional entity, lex specialis, proportionality
│   ├── 01-risk-assessment.md
│   ├── 02-statement-of-applicability.md
│   ├── 03-control-matrix.md      # THE front door artifact — see §9
│   ├── 04-limitations.md         # §11
│   ├── exceptions/               # one file per PolicyException + risk acceptance
│   ├── runbooks/                 # front-matter marks automated vs manual steps
│   └── evidence/                 # generated; gitignored except samples/
├── platform/
│   ├── talos/                    # machine configs, patches, audit policy
│   └── bare-metal/               # Ansible, CIS-hardened Ubuntu + k3s (phase 6)
├── bootstrap/
│   ├── install.sh                # idempotent, re-runnable, the only manual step
│   └── root-app.yaml
├── apps/                         # Argo CD Applications, sync-waved
├── infrastructure/
│   ├── cilium/                   # policies live here, not just the chart
│   ├── cert-manager/
│   ├── kyverno/                  # policies + exceptions
│   ├── argo-workflows/
│   ├── litmus/
│   ├── velero/                   # + MinIO
│   ├── trivy-operator/
│   └── observability/            # pluggable sink — see §7
├── drills/
│   ├── schema/drill-record.schema.json
│   ├── scenarios/                # one ScenarioSpec per file
│   ├── templates/                # Argo WorkflowTemplates
│   └── lib/                      # classify.py, clocks.py, emit.py
├── canary/                       # the RPO measurement workload
├── images/                       # apko/melange definitions
└── .github/workflows/            # build, sign, attest, weekly rebuild
```

---

## 6. The drill system (the core of the project)

Build this first. Everything else supports it.

### 6.1 The canary — how RPO becomes an integer

Deploy a small PVC-backed writer (Postgres, or simpler: an append-only writer to a PV) that inserts one row per second:

```
(counter BIGINT, ts TIMESTAMPTZ, prev_hash TEXT, hash TEXT)
```

The hash chain makes silent corruption detectable, which matters for the "restore succeeded but the data is wrong" failure mode that naive restore drills miss.

- **RPO** = `max(counter) before fault` − `max(counter) after restore`. An exact count of lost records, not an estimate.
- **RTO** = `t_recover` − `t_inject`, where `t_recover` is the first passing steady-state probe.

Charting measured RPO across many runs as the backup schedule changes is the most persuasive single artifact this project can produce. Build the chart.

### 6.2 Orchestration

**Argo Workflows** `CronWorkflow` per scenario. Scenarios are CRDs in Git, so drills are change-controlled like everything else.

Use an **exit handler** to emit the drill record on every path — success, failure, and timeout. Failed drills are more valuable evidence than passing ones and must never be silently dropped. A drill that fails to emit a record is itself a control failure and should alert.

**Litmus** for fault injection. Preferred over Chaos Mesh here because its probe model (`httpProbe`, `cmdProbe`, `promProbe` with `mode: Continuous`/`EOT`) maps directly onto steady-state hypothesis testing, and it emits a `ChaosResult` CR with verdict and probe success percentage — so part of the outcome tracking is already a Kubernetes object the log shipper can scrape. Chaos Mesh may be added later for higher-fidelity network/IO faults.

### 6.3 Scenario library

Build in this order. The first three prove the loop; the rest are additive.

1. **Node kill / NotReady** — tests rescheduling and PodDisruptionBudgets.
2. **Namespace deletion → Velero restore** into a *fresh* namespace. Never restore over the original; restoring in place proves nothing.
3. **PVC corruption → volume snapshot restore** — this is the one that exercises the canary hash chain.
4. **Control-plane / etcd loss → full rebuild + restore.** The Talos API makes this real rather than simulated.
5. **Network partition between namespaces** — doubles as validation that the NetworkPolicies actually deny.
6. **DNS failure / registry unreachable** — third-party dependency failure, Art. 28 relevance.
7. **Certificate expiry** — fast-forward a cert to expired. This is the failure mode that actually takes production clusters down and is almost never drilled.
8. **Credential compromise → shell spawn in container.** Validates the runtime-detection path end to end, and asserts not merely "we detected it" but "the alert reached the correct runbook within N seconds."
9. **Clock skew on a node** — because §4 claims time sync is load-bearing, so it must be drilled.

### 6.4 Timeline fields

Record these separately. The regulatory clock does not start at detection.

| Field | Meaning |
|---|---|
| `t_inject` | fault introduced |
| `t_detect` | first alert fired |
| `t_classify` | classification decision reached |
| `t_notify_due_dora` | `t_classify` + 4h, capped at `t_detect` + 24h |
| `t_notify_due_nis2` | `t_detect` + 24h |
| `t_recover` | steady-state probe passes |
| `t_verify` | hash-chain integrity check passes |

### 6.5 Classification as code

`drills/lib/classify.py` takes a drill record and returns `major | non-major` plus the criteria that tripped, implementing the DORA Art. 18 RTS criteria: clients/counterparties affected, data losses, duration and service downtime, geographical spread, economic impact, criticality of services affected, reputational impact.

This turns Art. 18 from something described into something executed. In a lab most inputs are synthetic — say so in the docstring rather than pretending the numbers are real.

### 6.6 Drill record schema

One flat JSON document per drill. Keep it boring.

```json
{
  "drill_id": "2026-07-27-etcd-loss-004",
  "scenario": "control-plane-loss",
  "git_sha": "a3f9c21",
  "cluster_profile": "full",
  "controls": ["DORA-Art11", "DORA-Art12", "NIS2-21.2.c", "ISO-A.8.13", "ISO-A.5.29"],
  "target_rto_seconds": 900,
  "target_rpo_seconds": 300,
  "measured_rto_seconds": 412,
  "measured_rpo_seconds": 63,
  "measured_rpo_records_lost": 63,
  "integrity_check": "pass",
  "verdict": "pass",
  "classification": "non-major",
  "classification_criteria_tripped": ["duration"],
  "manual_runbook_steps_required": 2,
  "t_inject": "2026-07-27T09:14:03Z",
  "t_detect": "2026-07-27T09:14:19Z",
  "t_classify": "2026-07-27T09:16:41Z",
  "t_recover": "2026-07-27T09:20:55Z",
  "t_verify": "2026-07-27T09:21:30Z",
  "artifacts": ["s3://drills/2026-07-27-etcd-loss-004/velero.log",
                "s3://drills/2026-07-27-etcd-loss-004/probe-timeline.json"]
}
```

`manual_runbook_steps_required` is deliberate. An honest count of steps still requiring a human is more credible than claiming full automation, and it gives the project a roadmap.

### 6.7 Evidence integrity

- Dedicated index with ILM and a defined retention period.
- Write-only ingest role; no delete permission on the drill index for cluster operators.
- Periodic snapshot to MinIO with **object lock** enabled.
- README explains *why*: evidence a cluster admin can silently delete is not evidence.

### 6.8 Incident response, not just recovery

- Drill → small script that opens a **ticket from a template** in a self-hosted ITSM tool (GLPI — chosen over GitHub Issues to keep incident tracking on the same self-hosted footing as everything else in this repo, Phase 11), pre-filled with the classification decision, both computed notification deadlines, and links to drill artifacts. The ticket tracker becomes a timestamped incident register.
- **Runbooks as code** in `docs/runbooks/`, each with machine-readable front matter listing steps and marking each `automated: true|false`. Alerts link to the specific runbook. The drill executes automated steps and records the manual ones as a gap.
- **Post-incident review** template auto-generated from the drill record (DORA Art. 13, ISO A.5.27).

---

## 7. Platform components

Deploy via Argo CD, all pinned, all with AppProject scoping (restricted source repos, destination namespaces, and allowed resource kinds — **never `project: default`**).

| Component | Purpose | Notes |
|---|---|---|
| Cilium | CNI, network policy, Hubble flow logs, WireGuard transparent encryption | Comes up with the cluster, not as a sync wave. Ship **actual policies**: default-deny per namespace, explicit allows, DNS-aware L7 egress. |
| cert-manager | Internal PKI | `ServerSideApply=true`. Does not equal mTLS — encryption comes from Cilium WireGuard. Say which. |
| Kyverno | Admission control | `validate.podSecurity` against PSS restricted. Per-rule `failureAction`. Ship the audit→enforce migration path with dates, not permanent audit mode. |
| Trivy Operator | Continuous vulnerability scanning | ISO A.8.8, NIS2 21(2)(d). |
| Velero + MinIO | Backup/restore | `Schedule` CRs in Git. In-cluster MinIO so no cloud account is needed. |
| Argo Workflows | Drill orchestration | |
| Litmus | Fault injection | |
| Observability sink | Logs, metrics, drill records, dashboards | **Pluggable** — see below. |

### Pluggable observability

Elastic + Fleet + Kibana is realistically 6–8 GB before indexing anything, which conflicts with the deployability goal. Design against an interface:

- `core` profile → lightweight sink (Loki/OpenSearch/plain-file).
- `full` profile → Elastic + Fleet + runtime eBPF agent.

Designing against the interface rather than the vendor is itself a point in the project's favour, and should be a short note in the README.

**The eBPF runtime agent requires the P2 treatment**: narrow capabilities (`CAP_BPF`, `CAP_PERFMON`, and `CAP_SYS_ADMIN` only if genuinely required) rather than blanket `privileged: true`; a committed `PolicyException` scoped to that exact workload; a written risk acceptance in `docs/exceptions/`; and deployment to a namespace where the admission webhook is actually active.

---

## 8. Supply chain

- **Images built with apko + melange (Wolfi).** Declarative, near-zero CVE, reproducible, native SBOM generation.
- **Signed with cosign keyless** — GitHub OIDC → Fulcio → Rekor.
- **Kyverno `verifyImages`** requiring the specific repository *and workflow identity*:

```yaml
attestors:
- entries:
  - keyless:
      subject: "https://github.com/OWNER/resilience-lab/.github/workflows/build.yaml@refs/heads/main"
      issuer: "https://token.actions.githubusercontent.com"
      rekor:
        url: https://rekor.sigstore.dev
```

- Additional `verifyImages` rule on the **SBOM attestation**.
- Registry allowlist; `:latest` banned; digests only.
- **Weekly scheduled rebuild** of all images regardless of source changes — a patch-management control (ISO A.8.8) that is trivial with Wolfi and impractical with most base images.
- **Generate the Register of Information from the image inventory and SBOMs** rather than maintaining it by hand. DORA Art. 28–30.
- Signed commits, branch protection with required review, and Argo CD GPG signature verification. "GitOps enforces change control" is only true if the Git history is tamper-evident.

---

## 9. The control traceability matrix

`docs/03-control-matrix.md` is the front door of the repository and the artifact an auditor or hiring manager actually wants. Generate it from annotations where possible so it cannot drift.

| Control ID | Requirement | Implemented by | Evidence artifact |
|---|---|---|---|
| DORA Art. 9 | Protection & prevention | `infrastructure/kyverno/policies/` | PolicyReports, admission denial logs |
| DORA Art. 11 | Response & recovery | `drills/scenarios/`, `infrastructure/velero/` | Drill records, measured RTO |
| DORA Art. 12 | Backup & restoration | `infrastructure/velero/schedules/` | Restore drill records, measured RPO |
| DORA Art. 18 | Classification | `drills/lib/classify.py` | Classification decisions in drill records |
| DORA Art. 19 | Reporting clocks | `drills/lib/clocks.py` | Computed deadlines per drill |
| DORA Art. 24–27 | Resilience testing | `drills/`, kube-bench job | Drill record history, CIS benchmark output |
| DORA Art. 28–30 | Third-party risk | `images/`, `verifyImages` policies | Generated Register of Information, SBOMs |
| NIS2 21(2)(c) | Business continuity | `drills/scenarios/` | Drill records |
| NIS2 Art. 23 | Reporting | `drills/lib/clocks.py` | Computed deadlines |
| ISO A.8.13 | Information backup | `infrastructure/velero/` | Restore drill records |
| ISO A.8.16 | Monitoring | observability profile | Detection latency (`t_detect` − `t_inject`) |
| ISO A.8.17 | Clock synchronisation | `platform/talos/` chrony config | NTP drift metrics, clock-skew drill |
| ISO A.8.29 | Security testing | CI pipeline, drills | Pipeline runs, drill records |

The evidence column must point at **generated artifacts**, not at YAML. That distinction is the whole point of the column.

---

## 10. Deployability

Put the tiering table at the very top of the README.

| Tier | Command | RAM | Contents |
|---|---|---|---|
| `core` | `make lab-core` | ~10 GB | Talos, Cilium, cert-manager, Kyverno, Argo CD, Trivy, lightweight log sink |
| `full` | `make lab-full` | ~28 GB | + Elastic/Fleet/eBPF agent, Velero + MinIO, Argo Workflows, Litmus |
| `dr` | `make lab-dr` | ~40 GB | + second cluster for cross-cluster restore drills |

Hard requirements:

- **Publish images to GHCR, pinned by digest.** Building from source is opt-in (`make images`), never required.
- **Two commands to a working cluster.** More than that and it will not get run.
- **`make drill SCENARIO=etcd-loss`** — one command that injects, recovers, and prints the drill record. This is the demo.
- **Assume nobody deploys it.** Most reviewers will not. Put an asciinema recording of `make drill`, a screenshot of the RTO/RPO trend chart, and a sample generated evidence report directly in the README. Deployability proves it is real; the recording is what actually gets seen.

---

## 11. Stated limitations

`docs/04-limitations.md`. Naming these is a stronger signal than pretending they do not exist — it is the difference between having read the regulation and having read a blog post about it.

- **DORA Art. 26 threat-led penetration testing (TLPT)** cannot be demonstrated in a lab. TIBER-EU style red teaming requires scope, threat intelligence, and independent testers.
- **Third-party contractual arrangements** (Art. 28–30) are simulated. Register of Information fields relating to contracts, exit strategies, and subcontracting chains are synthetic.
- **No relationship with a competent authority.** Reporting deadlines are computed and logged; nothing is submitted anywhere.
- **Classification inputs are synthetic** — client counts and economic impact are lab fixtures.
- **ISO 27001 requires an ISMS**, including management review, internal audit, and continual improvement (Clauses 4–10). This repo implements a subset of Annex A controls only.
- **Single-operator lab**, so segregation of duties is asserted through branch protection rather than genuinely enforced across people.

---

## 12. Build order

Do not build breadth-first. Get one drill measuring one number end to end before adding scenarios.

| Phase | Deliverable | Done when |
|---|---|---|
| 0 | `docs/00-scope.md`, control matrix skeleton, repo layout, Makefile stubs | Scope decisions written down |
| 1 | Talos cluster + Cilium + Argo CD + SOPS, AppProjects scoped, everything pinned | `make lab-core` works twice in a row from clean |
| 2 | Canary workload + drill record schema + emitter + log sink | Canary writes, hash chain verifies |
| 3 | Velero + MinIO + **scenario 2** (namespace delete → restore) | `make drill SCENARIO=ns-restore` prints a measured RTO **and** RPO |
| 4 | Kyverno policies + exceptions + audit→enforce plan; API audit logging shipping | A privileged pod is denied; the agent exception is documented |
| 5 | Platform/landing-zone generalization — `docs/00-scope.md` reframed from single-entity to platform+tenant | Docs are internally consistent; no stale single-tenant claims remain |
| 6 | Network segmentation: Cilium `CiliumNetworkPolicy` default-deny plus explicit allows, one namespace at a time, each verified against real observed traffic (Hubble, every node agent) before *and* after enforcement | All 8 core platform namespaces segmented; a real functional test specific to each namespace (a backup, a GitOps sync, the admission webhook, a DNS lookup) passes under genuine enforcement, not just a clean `kubectl apply` |
| 7 | PKI foundation: offline Root CA signs an Intermediate CA; cert-manager `ca`-type `ClusterIssuer` issues real leaf certs | Services serve real, cert-manager-issued TLS, verified via the certificate's issuer chain |
| 8 | IAM: Keycloak (+ LDAP federation), platform services switched from local admin accounts to OIDC SSO, real RBAC demonstrated | Login goes through Keycloak, not a local password; RBAC roles are actually enforced |
| 9 | Detection layer: alerting rules firing on defined conditions; `t_detect` wired into the drill record schema/emitter for the first time | A drill run produces a real, non-null `t_detect` |
| 10 | Scenarios 1, 3, 4, 5; RTO/RPO trend dashboard | Drill history chartable |
| 11 | Incident response: classification, clocks (fed by real `t_detect`), self-hosted GLPI ticket automation, runbooks | Drill opens a ticket with both deadlines computed from real timestamps |
| 12 | Supply chain: apko images, cosign, `verifyImages`, generated RoI | Unsigned image is rejected at admission |
| 13 | Endpoint runtime security; scenario 8 (credential compromise → shell spawn → runtime detection) | Alert reaches the correct runbook within the drill's own measured N seconds |
| 14 | Scenarios 6, 7, 9; kube-bench; evidence report generator | `make evidence` produces the report |
| 15 | README polish, asciinema, screenshots, `bare-metal/` Ansible alternative | A stranger can run it |
| 16 | Security operations: real vulnerability scanning + tracking, continuous endpoint/config monitoring, standing security-posture dashboard | A dashboard shows real, live CVE counts by severity and days-open per image, sourced from an actual scanner run, not asserted |

**Phase 3 is the milestone that matters.** Once one drill produces one honestly measured RTO and RPO, the project's thesis is proven and everything after is expansion.

**Phases 5–15, revised twice (build-spec originally specified 5–9):** Phase 4's completion surfaced a
security-plane scope expansion — SIEM/detection, continuous scanning, endpoint runtime security,
and (added after a real access-management bug: an auto-generated credential silently changed
between two GitOps syncs) IAM and PKI. Access management had zero control-matrix representation
and was judged more foundational than SIEM/scanning/endpoint, which still route through
individually-fragile logins without it — so PKI and IAM were inserted directly after the
platform/tenant reframing (5), ahead of everything else. The original "Phase 6" (supply chain)
also split into scanning (folded into the detection work) and build-time signing (now Phase 12) —
runtime vulnerability scanning and build-time provenance are different concerns at very different
effort levels, not one deliverable. Phase 11 (incident response) has a hard dependency on Phase
9's `t_detect` that didn't exist in the original ordering, where incident response preceded a
detection layer that was never built.

A second revision then inserted **network segmentation** (now Phase 6, ahead of PKI/IAM) once
work actually started: it was faster and cheaper than PKI/IAM, used infrastructure that had been
live since Phase 1 (Cilium+Hubble, just never had policies written), and is what makes a
"regulatory scope boundary" claim technically verifiable rather than asserted — the same
reasoning that motivated inserting PKI/IAM in the first revision, just resolved by building the
cheaper thing first. This bumped every phase 6–14 up by one. Consistent with this file's own
build-order discipline ("do not build breadth-first"), this renumbering happened only once
network segmentation was actually complete and verified against the real cluster — not
speculatively, the way the first revision's numbers were also revised once more before anything
in that range was built.

**Phase 16, added after Phase 15 was already on the roadmap:** every earlier security-plane
phase (9, 10, 12, 13) proves one specific, narrow thing — a detection rule fires, a drill
recovers, an image is signed, a shell spawn is caught. None of them add up to a standing security
operations posture: something continuously watching for risk independent of whether a drill
happens to be running. Phase 16 closes that gap, organized the same way a mature security
program's control catalog would be (a real-world audit checklist maps cleanly onto it), without
naming or citing any specific external catalog in this repo's own docs — this project already has
its explicit regulatory anchors (DORA/NIS2/ISO 27001) and doesn't need a second, unrelated
framework layered on top just for vocabulary. Scope:

- **Vulnerability management.** A real scanner (Trivy Operator is the leading candidate — its
  `VulnerabilityReport` CRDs are the natural source) producing real CVE findings per image, not
  assumed absent the way `infrastructure/trivy-operator/`'s empty placeholder directory currently
  implies it exists. A dashboard (Grafana, reusing this repo's existing pattern) showing severity,
  first-detected date, and age-against-an-SLA-window per finding — the SLA windows themselves are
  a policy choice this repo will state as a synthetic/example policy (same "say so, don't fake it"
  discipline as `drills/lib/classification-profiles.json`), not claimed as a real enterprise SLA.
- **Continuous security monitoring.** Standing Grafana Alerting rules that fire independent of any
  drill run — failed Keycloak authentications, privilege/role changes, unexpected process
  execution outside the canary namespace (Tetragon's own coverage is canary-scoped today) — versus
  today's detection layer, which only proves itself when a drill deliberately triggers it.
- **Endpoint/configuration baseline compliance.** `kube-bench` (CIS Kubernetes Benchmark), tracked
  over time rather than a one-off report — ties into, and likely absorbs, Phase 14's own
  `kube-bench` line item.
- **Living asset inventory.** Connects Phase 12's generated Register of Information and GLPI's
  asset-management module (flagged as a future payoff since Phase 11) into something queryable on
  an ongoing basis, not a static generated snapshot.

---

## 13. Instructions to the coding assistant

- Work phase by phase. Do not start a phase until the previous phase's "done when" is actually true.
- Before adding any component, ask: does it enforce a control, produce evidence, or improve deployability? If none, do not add it.
- When you write a claim in a README or comment, immediately verify a file implements it. If none does, either write the file or delete the claim.
- Pin every version at the moment you add it. Never write `latest`, `stable`, or `HEAD`.
- When a security tool requires elevated privilege, do not silently grant it — produce the exception file and the risk acceptance in the same commit.
- Prefer boring, well-documented mechanisms over clever ones. This project is judged on judgement, not novelty.
- Where a lab genuinely cannot demonstrate something, add it to `docs/04-limitations.md` rather than faking it.
- Version and chart numbers in this document are illustrative. Check current releases at build time and pin to what actually exists.
