# elastic-dora-blueprint

A GitOps Kubernetes reference architecture demonstrating DORA, NIS2, and ISO 27001 controls,
with automated recovery drills that emit measured evidence.

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
(RTO 110s, RPO 71 records, hash-chain `integrity_check: pass`). Asciinema recording and RTO/RPO
trend chart across multiple runs are still outstanding — see Phase 8/9.

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

This repo is being built phase-by-phase per the build spec, breadth-last. Current phase: **5**.
Phase 3 was the milestone the build spec names as the point the project's thesis is proven —
everything after this is expansion, not proof of concept.

| Phase | Deliverable | Done when | Status |
|---|---|---|---|
| 0 | Scope docs, control-matrix skeleton, repo layout, Makefile stubs | Scope decisions written down | done |
| 1 | Talos + Cilium + Argo CD + SOPS, AppProjects scoped, everything pinned | `make lab-core` works twice in a row from clean | done |
| 2 | Canary workload + drill record schema + emitter + log sink | Canary writes, hash chain verifies | done |
| 3 | Velero + MinIO + scenario 2 (namespace delete → restore) | `make drill SCENARIO=ns-restore` prints measured RTO and RPO | done |
| 4 | Kyverno policies + exceptions + audit→enforce plan; API audit logging shipping | A privileged pod is denied; the agent exception is documented | done |

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

Phases 5–9 are described in full in `BUILD-SPEC.md` §12 and are out of scope for the current
milestone.

## Docs

- [`docs/00-scope.md`](docs/00-scope.md) — notional entity, lex specialis reasoning, DORA Art. 16 analysis
- [`docs/03-control-matrix.md`](docs/03-control-matrix.md) — control traceability, the front-door artifact
- [`docs/04-limitations.md`](docs/04-limitations.md) — what this lab cannot demonstrate, and why
- [`BUILD-SPEC.md`](BUILD-SPEC.md) — the full build specification this repo follows

## Observability

Pluggable by design, not by vendor: `core` profile targets a lightweight sink; `full` profile
adds Elastic/Fleet/eBPF. See `infrastructure/observability/`.
