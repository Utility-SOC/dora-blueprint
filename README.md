# elastic-dora-blueprint

A GitOps Kubernetes reference architecture demonstrating DORA, NIS2, and ISO 27001 controls,
with automated recovery drills that emit measured evidence. As of Phase 5, this is framed as a
security control plane / landing zone that a regulated tenant application is onboarded onto —
see `docs/00-scope.md` §0.1 for the platform-vs-tenant distinction.

> Most compliance repos assert their recovery objectives. This one measures them, on a
> schedule, and stores the results as tamper-evident evidence mapped to specific regulatory
> articles.

**What this is not:** a compliance product, a certification, or a claim that any organisation
running it is compliant. ISO 27001 certifies a management system, not a toolchain. DORA and
NIS2 apply to regulated entities, not repositories. See `docs/00-scope.md` and
`docs/04-limitations.md`.

**The thesis is proven as of Phase 3:** `make drill SCENARIO=ns-restore` deletes the canary
namespace, restores it from a real Velero backup into a freshly-named namespace, and prints a
*measured* RTO and RPO — not asserted numbers. Sample record:
[`docs/evidence/samples/ns-restore-20260728152755.json`](docs/evidence/samples/ns-restore-20260728152755.json)
(RTO 110s, RPO 71 records, hash-chain `integrity_check: pass`). RTO/RPO trend chart across
multiple runs is Phase 10; asciinema recording is Phase 15 — both still outstanding.

## Tiers

| Tier | Command | RAM | Contents |
|---|---|---|---|
| `core` | `make lab-core` | ~10 GB | Talos, Cilium, cert-manager, Kyverno, Argo CD, Trivy, lightweight log sink |
| `full` | `make lab-full` | ~28 GB | + Elastic/Fleet/eBPF agent, Velero + MinIO, Argo Workflows, Litmus |
| `dr` | `make lab-dr` | ~40 GB | + second cluster for cross-cluster restore drills |

Two commands to a working cluster; a third injects a fault, recovers, and prints a measured
RTO/RPO:

```bash
make lab-core
make drill SCENARIO=ns-restore
```

*(Both work as of Phase 3.)*

## Build order and status

This repo is being built phase-by-phase per the build spec, breadth-last. Current phase: **7**.
Phase 3 was the milestone the build spec names as the point the project's thesis is proven —
everything after this is expansion, not proof of concept. The build order past Phase 4 was
revised once a security-plane scope expansion (SIEM/detection, scanning, endpoint, IAM/PKI)
surfaced — see `BUILD-SPEC.md` §12's note on the revision for the full rationale.

| Phase | Deliverable | Done when | Status |
|---|---|---|---|
| 0 | Scope docs, control-matrix skeleton, repo layout, Makefile stubs | Scope decisions written down | done |
| 1 | Talos + Cilium + Argo CD + SOPS, AppProjects scoped, everything pinned | `make lab-core` works twice in a row from clean | done |
| 2 | Canary workload + drill record schema + emitter + log sink | Canary writes, hash chain verifies | done |
| 3 | Velero + MinIO + scenario 2 (namespace delete → restore) | `make drill SCENARIO=ns-restore` prints measured RTO and RPO | done |
| 4 | Kyverno policies + exceptions + audit→enforce plan; API audit logging shipping | A privileged pod is denied; the agent exception is documented | done |
| 5 | Platform/landing-zone generalization — `docs/00-scope.md` reframed from single-entity to platform+tenant | Docs are internally consistent; no stale single-tenant claims remain | done |
| 6 | Network segmentation: Cilium `CiliumNetworkPolicy` default-deny + explicit allows across all 8 core platform namespaces, each verified against real traffic before and after enforcement | A real functional test (backup, GitOps sync, admission webhook, DNS lookup) passes under genuine enforcement in every namespace | done |

Phase 1 notes: `make lab-core` brings up a pinned Talos v1.13.7 cluster (Docker provisioner,
k8s v1.36.2), Cilium v1.19.6, and Argo CD v3.4.5, with a scoped AppProject and a working
app-of-apps syncing from this repo. Three real bugs found and fixed by actually running it —
not just reading the spec — are documented in `platform/talos/README.md`: Talos has no chrony,
Kubernetes Secrets encryption at rest is a Talos default (attempting to hand-configure it
crashes cluster creation), and Cilium on Talos-in-Docker needs an explicit, narrower capability
set than its bare-metal defaults assume.

Phase 2 notes: the canary (`canary/`) writes one hash-chained SQLite row/sec, verified live —
`kubectl exec deploy/canary-writer -n canary -- python3 /scripts/verify.py` reports
`integrity_check: pass` against the running chain. `drills/schema/drill-record.schema.json` and
the dependency-free `drills/lib/emit.py` give a drill record its shape ahead of any scenario
producing one. The log sink is Loki (SingleBinary, filesystem storage) + Grafana Alloy — Alloy
over the deprecated Promtail, `loki.source.kubernetes` (reads pod logs via the API server) over
host-path tailing — confirmed end-to-end by querying Loki directly for the canary's own log
lines. This was also the first real GitOps rollout: everything in `apps/` deployed by Argo CD
syncing this repo, no manual `kubectl apply` beyond the `bootstrap/` exception. Talos ships no
CSI driver, so `local-path-provisioner` (`infrastructure/local-path-provisioner/`) had to be
added first to get a default StorageClass at all — docs.siderolabs.com's own example host path
(`/var/mnt/...`) doesn't work without a Talos user-volume declaration this repo doesn't make;
using a plain `/var` path instead, per `infrastructure/local-path-provisioner/kustomization.yaml`.

Phase 3 notes: the ns-restore scenario (`drills/scenarios/ns-restore.yaml`,
`drills/templates/ns-restore-workflowtemplate.yaml`) runs as an Argo Workflow — capture the
canary's live counter, delete its namespace, restore the most recent Velero backup into a
freshly-named namespace (never in place — "restoring in place proves nothing"), wait for the
restored writer to report Ready, verify its hash chain, and compute RTO/RPO from real
timestamps and an exact record count. The real blocker here wasn't the drill logic — it was
storage: `local-path-provisioner`'s PVs are `hostPath`-typed, and Velero's own docs are explicit
that File System Backup does not support that type. A full drill run completed with no errors
anywhere and silently restored an *empty* volume before this was caught by checking the restored
data directly rather than trusting the "Completed" status. Fixed with a second, narrowly-scoped
provisioner (`apps/openebs-localpv.yaml`, OpenEBS's localpv-provisioner, which produces
Velero-FSB-compatible `local`-typed PVs) used only for the canary's volume — Loki and MinIO stay
on `local-path-provisioner`, since they're never backed up. That in turn needed an explicit
`machine.kubelet.extraMounts` bind (`platform/talos/patches/common.yaml`): Talos runs kubelet in
its own isolated container, and the `local` PV type's kubelet volume plugin does its own
path-visibility check that fails closed without it — unlike plain `hostPath`, which gets broad
enough default access to work unprompted. A separate, unrelated discovery along the way: the
Docker provisioner's 2GiB-per-node memory default was too tight once real workloads landed,
and starved `kube-controller-manager` into an hours-long crash loop that looked like an RBAC or
scheduling bug until `docker stats` showed 93% memory usage — `bootstrap/install.sh` now sets
explicit, larger per-node memory limits.

Phase 4 notes: Kyverno (`apps/kyverno.yaml`, `apps/kyverno-policies.yaml`) enforces PSS
`restricted` cluster-wide (`infrastructure/kyverno/policies/require-pod-security-restricted.yaml`),
in `Enforce` from the start rather than a permanent audit mode — every currently-privileged
workload already had a scoped, documented exception (`docs/exceptions/`) verified before
enforcement went live. Two of those four exceptions ended up as `exclude` blocks on the
ClusterPolicy itself rather than `PolicyException` objects, after hitting a confirmed open
Kyverno bug ([kyverno/kyverno#12888](https://github.com/kyverno/kyverno/issues/12888)) where a
`podSecurity` PolicyException can't suppress a pod-level (not container-scoped) violation, and
separately, Kyverno's autogen mechanism validating a DaemonSet's embedded pod template as a
second, independent admission check that a Pod-only PolicyException never reaches. The second
Phase 4 deliverable — API audit logging shipping, not just an audit policy writing to a file no
one reads — needed Alloy switched from a single Deployment to a DaemonSet pinned to the
control-plane node (the audit log is a *file*, not container stdout, so the existing
`loki.source.kubernetes` collection path structurally can't see it), an explicit
`machine.kubelet.extraMounts` bind for the same "Talos's kubelet runs in an isolated mount
namespace" reason Phase 3's `local` PV type needed one, and a 10MB `max_line_size` bump on Loki
after its 256KB default silently dropped `RequestResponse`-level audit entries — exactly the
secrets/RBAC-change entries build-spec §4 asks this audit policy to capture, which would have
made "shipping" true in name only. Recreating already-running pods to pick up config changes
surfaced two more grandfathered PSS gaps (Alloy, Loki) that predated Kyverno's admission
enforcement and had simply never been re-validated — found and fixed the same way as Phase 3's
canary/drill-workflow gaps, by checking directly rather than assuming "already Running" meant
"compliant." Evidence:
[`docs/evidence/samples/kyverno-admission-20260728202845.txt`](docs/evidence/samples/kyverno-admission-20260728202845.txt).
Re-ran `make drill SCENARIO=ns-restore` once all of the above landed, to prove Phase 3's
capability still works end-to-end rather than assume it — the first two attempts both failed at
admission (Argo's emissary executor injects its own init/wait containers with no
`securityContext`, which no WorkflowTemplate-level setting can cover, since
`allowPrivilegeEscalation`/`capabilities` have no pod-level fallback in the Kubernetes API at
all), fixed with `executor.securityContext` in `apps/argo-workflows.yaml`. Third attempt: verdict
`pass`, RTO 147s, integrity check passed —
[`docs/evidence/samples/ns-restore-20260728204154.json`](docs/evidence/samples/ns-restore-20260728204154.json).

Phase 5 notes: docs-only — restructured `docs/00-scope.md` from a single "Meridian Pay is the
lab" framing into a platform/tenant model (§0.1 splits into "the platform" and "its example
tenant"; new §0.6 lists which mechanisms are platform-level versus tenant-specific), updated
`docs/03-control-matrix.md`'s reading notes and every `not yet generated` phase marker to match
the renumbered build order, and rewrote `BUILD-SPEC.md` §12's table. This phase touches no
cluster-facing files, so unlike every phase before it there's no "real bug found by running it"
moment to report — the equivalent discipline was a proofreading/consistency pass: grepping for
stale single-tenant claims, cross-checking phase-number references across all four documents, and
re-reading every new sentence against build-spec §13's "does this assert a capability that
exists?" question, rather than trusting a runtime check that doesn't apply here.

Phase 6 notes: `infrastructure/cilium/` went from an empty, long-flagged directory to a full
default-deny-plus-explicit-allow policy set across all 8 core platform namespaces, built and
verified one namespace at a time, lowest-risk first (`canary` → `observability` → `velero` →
`argo-workflows` → `openebs`/`local-path-storage` → `kyverno` → `argocd` → `kube-system`). Every
namespace's rules came from real Hubble traffic (every node agent, not an architecture diagram),
audit-mode-verified, then enforced and re-verified with a functional test specific to that
namespace. `kyverno` was the highest deliberate-risk step — its admission webhook runs
`failurePolicy: Fail`, so a wrong rule would have broken cluster-wide resource admission, not
just this namespace — and it turned up a genuinely non-obvious finding: the real webhook call
and the local kubelet readiness probe arrive as two different Cilium identities (`remote-node`
vs. `host`) despite looking like one traffic flow. `kube-system` then found real bugs live, not
just in logs: an early coredns ingress rule (`fromEndpoints: [{}]`) broke cluster DNS outright,
because Cilium scopes an empty `fromEndpoints` to the *same namespace as the policy* — the same
gotcha as native K8s NetworkPolicy's `podSelector: {}` without a `namespaceSelector` — caught via
a real failed `nslookup` and fixed within the same test cycle. A second gap surfaced right after:
coredns also needed egress to Talos's own per-node link-local DNS resolver, the actual path
external names like `github.com` resolve through — an initial "no external DNS observed"
assumption was simply wrong. Along the way, unrelated to kube-system itself, found and fixed a
real production gap in the earlier `velero` pass: Kopia repository-maintenance CronJobs
(`velero.io/repo-name` label, missed by the original hosting-pod policies) had been failing
continuously against MinIO — confirmed fixed by watching a live CronJob run actually succeed.
`kube-system`'s own CiliumNetworkPolicies are deliberately **not** Argo CD-managed: a real sync
attempt surfaced that the `platform` AppProject's destination allowlist already excludes
`kube-system`, kept rather than widened, given what this phase had just demonstrated about how
easily a kube-system mistake cascades. Full reasoning in
`infrastructure/cilium/kube-system/README.md`; evidence:
[`docs/evidence/samples/cilium-network-segmentation-20260729015300.txt`](docs/evidence/samples/cilium-network-segmentation-20260729015300.txt).
Also added `docs/05-shared-responsibility.md`, expanding `docs/00-scope.md` §0.6's two-list
sketch into a full control-by-control platform-vs-tenant breakdown now that network segmentation
gives it a second real platform control (alongside Kyverno) to describe.

Phases 7–15 are described in full in `BUILD-SPEC.md` §12 and are out of scope for the current
milestone.

## Docs

- [`docs/00-scope.md`](docs/00-scope.md) — platform/tenant framing, lex specialis reasoning, per-tenant DORA Art. 16 analysis
- [`docs/03-control-matrix.md`](docs/03-control-matrix.md) — control traceability, the front-door artifact
- [`docs/04-limitations.md`](docs/04-limitations.md) — what this lab cannot demonstrate, and why
- [`docs/05-shared-responsibility.md`](docs/05-shared-responsibility.md) — control-by-control platform-vs-tenant breakdown
- [`BUILD-SPEC.md`](BUILD-SPEC.md) — the full build specification this repo follows

## Observability

Pluggable by design, not by vendor: `core` profile targets a lightweight sink; `full` profile
adds Elastic/Fleet/eBPF. See `infrastructure/observability/`.
