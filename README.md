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

*Asciinema recording of `make drill`, RTO/RPO trend chart, and a sample evidence report belong
here once Phase 3/8 produce them — placeholders only until then, per build-spec P1: no claim
without an implementation.*

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

*(`make lab-core` works as of Phase 1. `make drill` is still a stub — see Makefile and build
order below.)*

## Build order and status

This repo is being built phase-by-phase per the build spec, breadth-last. Current phase: **2**.

| Phase | Deliverable | Done when | Status |
|---|---|---|---|
| 0 | Scope docs, control-matrix skeleton, repo layout, Makefile stubs | Scope decisions written down | done |
| 1 | Talos + Cilium + Argo CD + SOPS, AppProjects scoped, everything pinned | `make lab-core` works twice in a row from clean | done |
| 2 | Canary workload + drill record schema + emitter + log sink | Canary writes, hash chain verifies | not started |
| 3 | Velero + MinIO + scenario 2 (namespace delete → restore) | `make drill SCENARIO=ns-restore` prints measured RTO and RPO | not started |

Phase 1 notes: `make lab-core` brings up a pinned Talos v1.13.7 cluster (Docker provisioner,
k8s v1.36.2), Cilium v1.19.6, and Argo CD v3.4.5, with a scoped AppProject and a working
app-of-apps syncing from this repo. Three real bugs found and fixed by actually running it —
not just reading the spec — are documented in `platform/talos/README.md`: Talos has no chrony,
Kubernetes Secrets encryption at rest is a Talos default (attempting to hand-configure it
crashes cluster creation), and Cilium on Talos-in-Docker needs an explicit, narrower capability
set than its bare-metal defaults assume.

Phases 4–9 are described in full in `BUILD-SPEC.md` §12 and are out of scope for the current
milestone (Phase 3).

## Docs

- [`docs/00-scope.md`](docs/00-scope.md) — notional entity, lex specialis reasoning, DORA Art. 16 analysis
- [`docs/03-control-matrix.md`](docs/03-control-matrix.md) — control traceability, the front-door artifact
- [`docs/04-limitations.md`](docs/04-limitations.md) — what this lab cannot demonstrate, and why
- [`BUILD-SPEC.md`](BUILD-SPEC.md) — the full build specification this repo follows

## Observability

Pluggable by design, not by vendor: `core` profile targets a lightweight sink; `full` profile
adds Elastic/Fleet/eBPF. See `infrastructure/observability/`.
