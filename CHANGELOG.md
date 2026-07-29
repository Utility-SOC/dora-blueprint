# Changelog

Detailed, phase-by-phase build notes: what shipped, and the real bugs found and fixed by
actually running each phase against the live cluster — not assumed from a clean `kubectl apply`
or a passing sync. `README.md` keeps only a compact status table and roadmap; this file is where
the "how do I know this is real" detail lives. Evidence artifacts referenced below live in
`docs/evidence/samples/`.

## Phase 1 — Talos + Cilium + Argo CD + SOPS

`make lab-core` brings up a pinned Talos v1.13.7 cluster (Docker provisioner, k8s v1.36.2),
Cilium v1.19.6, and Argo CD v3.4.5, with a scoped AppProject and a working app-of-apps syncing
from this repo. Three real bugs found and fixed by actually running it, documented in
`platform/talos/README.md`: Talos has no chrony, Kubernetes Secrets encryption at rest is a
Talos default (hand-configuring it crashes cluster creation), and Cilium on Talos-in-Docker
needs an explicit, narrower capability set than its bare-metal defaults assume.

## Phase 2 — Canary workload + drill record schema + log sink

The canary (`canary/`) writes one hash-chained SQLite row/sec, verified live —
`kubectl exec deploy/canary-writer -n canary -- python3 /scripts/verify.py` reports
`integrity_check: pass`. `drills/schema/drill-record.schema.json` and the dependency-free
`drills/lib/emit.py` give a drill record its shape ahead of any scenario producing one. Log
sink: Loki (SingleBinary) + Grafana Alloy (`loki.source.kubernetes`, not host-path tailing —
sidesteps Talos's `/var/lib/docker/containers` not existing). First real GitOps rollout:
everything in `apps/` deployed by Argo CD, no manual `kubectl apply` beyond `bootstrap/`. Talos
ships no CSI driver, so `local-path-provisioner` had to be added first for a default
StorageClass — docs.siderolabs.com's example host path doesn't work without a Talos user-volume
declaration this repo doesn't make; used a plain `/var` path instead.

## Phase 3 — Velero + MinIO + ns-restore drill (thesis proven)

The ns-restore scenario runs as an Argo Workflow: capture the canary's live counter, delete its
namespace, restore the most recent Velero backup into a *freshly-named* namespace (never in
place — "restoring in place proves nothing"), wait for Ready, verify the hash chain, compute
RTO/RPO from real timestamps and an exact record count. Real blocker: `local-path-provisioner`'s
PVs are `hostPath`-typed, and Velero's File System Backup doesn't support that type — a full
drill run completed with zero errors and silently restored an *empty* volume before this was
caught by checking the restored data directly, not trusting "Completed" status. Fixed with a
second, narrowly-scoped provisioner (OpenEBS localpv, `local`-typed PVs) used only for the
canary's volume. That needed an explicit `machine.kubelet.extraMounts` bind — Talos's kubelet
runs in its own isolated mount namespace, and `local`-typed PVs do their own path-visibility
check that `hostPath` doesn't. Separately: the Docker provisioner's 2GiB-per-node memory default
starved `kube-controller-manager` into an hours-long crash loop that looked like an RBAC bug
until `docker stats` showed 93% memory usage — `bootstrap/install.sh` now sets explicit, larger
per-node memory limits.

Evidence: [`ns-restore-20260728152755.json`](docs/evidence/samples/ns-restore-20260728152755.json)
— RTO 110s, RPO 71 records, `integrity_check: pass`.

## Phase 4 — Kyverno PSS enforcement + API audit logging

Kyverno enforces PSS `restricted` cluster-wide, in `Enforce` from the start — every
currently-privileged workload already had a scoped, documented exception (`docs/exceptions/`)
verified before enforcement went live. Two exceptions ended up as `exclude` blocks on the
ClusterPolicy rather than `PolicyException` objects, after hitting a confirmed open Kyverno bug
([kyverno/kyverno#12888](https://github.com/kyverno/kyverno/issues/12888)) where a `podSecurity`
PolicyException can't suppress a pod-level violation. API audit logging needed Alloy switched
from a Deployment to a control-plane-pinned DaemonSet (the audit log is a *file*, not stdout),
an explicit `machine.kubelet.extraMounts` bind, and a 10MB `max_line_size` bump on Loki after its
256KB default silently dropped `RequestResponse`-level entries — exactly the secrets/RBAC-change
entries this policy exists to capture. Re-running `make drill SCENARIO=ns-restore` after all of
the above surfaced a fresh admission failure (Argo's emissary executor injects init/wait
containers with no `securityContext`, uncoverable at the WorkflowTemplate level), fixed with
`executor.securityContext` in `apps/argo-workflows.yaml`.

Evidence: [`kyverno-admission-20260728202845.txt`](docs/evidence/samples/kyverno-admission-20260728202845.txt),
[`ns-restore-20260728204154.json`](docs/evidence/samples/ns-restore-20260728204154.json) (RTO 147s).

## Phase 5 — Platform/tenant reframing

Docs-only: restructured `docs/00-scope.md` from a single "Meridian Pay is the lab" framing into
a platform/tenant model, updated `docs/03-control-matrix.md`'s reading notes, rewrote
`BUILD-SPEC.md` §12's table. No cluster-facing changes, so the verification discipline was a
proofreading/consistency pass rather than a runtime check.

## Phase 6 — Network segmentation

`infrastructure/cilium/` went from an empty directory to a full default-deny-plus-explicit-allow
policy set across all 8 core platform namespaces, built one at a time, lowest-risk first
(`canary` → `observability` → `velero` → `argo-workflows` → `openebs`/`local-path-storage` →
`kyverno` → `argocd` → `kube-system`), each audit-mode-verified against real Hubble traffic then
enforced and re-verified with a functional test. `kyverno` was the highest deliberate-risk step
— its webhook runs `failurePolicy: Fail` — and turned up a non-obvious finding: the real webhook
call and the local kubelet probe arrive as two different Cilium identities (`remote-node` vs.
`host`) despite looking like one flow. `kube-system` found two real bugs live: an early coredns
ingress rule (`fromEndpoints: [{}]`) broke cluster DNS outright — Cilium scopes an empty
`fromEndpoints` to the *same namespace as the policy*, the same gotcha as native K8s
NetworkPolicy's `podSelector: {}` without a `namespaceSelector` — and coredns also needed egress
to Talos's own per-node link-local DNS resolver for external names. Unrelated find: Velero's
Kopia repository-maintenance CronJobs had been failing continuously against MinIO, missed by the
original velero-namespace pass. `kube-system`'s policies are applied out-of-band (the AppProject
already excludes that namespace from its destinations) — see
`infrastructure/cilium/kube-system/README.md`.

Evidence: [`cilium-network-segmentation-20260729015300.txt`](docs/evidence/samples/cilium-network-segmentation-20260729015300.txt).

## Phase 7 — PKI foundation

Real offline-root/online-intermediate PKI, not a flat `selfSigned` `ClusterIssuer`. Root CA (RSA
4096, 10yr) and Intermediate CA (RSA 4096, 5yr) generated in a network-isolated Docker container
on appserv (`--network none`, confirmed — only a loopback interface) standing in for a literal
throwaway VM, since appserv has no hypervisor tooling. Real gotcha: a first attempt bind-mounted
the Root CA's private key into the "isolated" container, meaning it sat in a plain
host-readable directory the whole time — fixed by moving it into the container's own filesystem
layer before extracting anything. cert-manager's chart defaults leader-election RBAC to
`kube-system` for legacy reasons, caught by a real sync failure and fixed with
`global.leaderElection.namespace`. Real leaf certs for Argo CD and Grafana surfaced two more
bugs: Grafana's chart's generic `extraVolumes` silently falls back to `emptyDir` for a plain
`secret:` volume source (confirmed via `helm template`; the dedicated `extraSecretMounts` key is
what actually works), and switching `server.protocol` to `https` breaks Grafana's default
liveness/readiness probes, which don't parameterize scheme by protocol.

Runbook: `docs/runbooks/pki-root-ca-issuance.md`. Evidence:
[`pki-chain-verification-20260729025500.txt`](docs/evidence/samples/pki-chain-verification-20260729025500.txt).

## Phase 8 — IAM (Keycloak + OpenLDAP + OIDC SSO + RBAC)

OpenLDAP (bare Deployment, `osixia/openldap`, no maintained free Helm chart exists) seeded with
two toy users in two groups (`alice`/platform-admins, `bob`/platform-viewers), federated into
Keycloak (`codecentric/keycloakx`) via `configure-realm.sh`'s `kcadm.sh`-scripted setup — chosen
over a hand-written realm-export JSON because LDAP federation's component-based schema is fragile
to get right by hand. Four real bugs: OpenLDAP's own init framework needs root, not just an
LDAP-specific chown step, confirmed by an A/B test (root boots cleanly; non-root prints one line
and dies); OpenLDAP's seed script wasn't idempotent across restarts, fixed with a real PVC;
Keycloak crash-looped three separate ways (a `startupProbe` override in the wrong shape, missing
`securityContext` fields, no default start command); and the exact cross-namespace-`matchLabels`
Cilium bug from Phase 6's coredns work recurred **twice** — OpenLDAP's ingress rule, then
Keycloak's egress rule to OpenLDAP, the second time despite being documented in the first file's
own comment. Argo CD's `argocd-cm`/`argocd-rbac-cm` were patched directly (no Helm values path —
Argo CD installs from upstream manifests) with `oidc.config` and a real `policy.csv`; Grafana got
an equivalent `auth.generic_oauth` block. Both keep local admin accounts active alongside OIDC,
deliberately, rather than a one-shot cutover. Verification hit an environment limit, not a code
bug: neither the sandboxed browser pane nor the Chrome extension could drive an actual browser
login, so RBAC was verified via real OIDC ID tokens presented as Bearer credentials against Argo
CD's own `can-i` API — the identical server-side validation path a browser login would exercise.

Evidence: [`keycloak-ldap-oidc-verification-20260729043900.txt`](docs/evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt),
[`argocd-rbac-verification-20260729045300.txt`](docs/evidence/samples/argocd-rbac-verification-20260729045300.txt).

## Phase 9 — Detection layer (Grafana Alerting, real `t_detect`)

A real Grafana Alerting rule watches the kube-apiserver audit log — shipped to Loki since Phase
4, no audit-policy change needed — for the exact real signal the ns-restore drill's own fault
injection produces. This finalizes the Grafana-vs-Elastic technology trial flagged back in
Phase 6/7: Grafana was already the most integrated option, and building the platform's actual
detection engine on it settled the comparison rather than standing up a second stack. `t_detect`
— "first alert fired," not something a drill self-reports — is captured by polling Grafana's own
live Alerting API immediately after fault injection, authenticated via a Viewer-scoped
service-account token and verifying the platform's real CA chain.

Five real bugs found and fixed by actually running drills, none assumed from a clean
provisioning apply: a bare `| json` LogQL parse tripped Loki's "maximum number of series (500)
reached" (fixed with explicit field extraction); pinning an explicit `uid` on the already-live
Loki datasource conflicted with Grafana's persisted SQLite state, crash-looping new pods (fixed
by wiping Grafana's PVC — its DB was never meant to be durable, same reasoning as Keycloak's
`dev-mem`, confirmed with the user first since it's destructive); the alert rule's threshold
expression rejected `queryType: range` results ("only reduced data can be alerted on," fixed
with `queryType: instant`); even after that fix, a 60-second lookback window was too tight
against real shipping+ingestion+evaluation latency (a genuine ~66-second gap, confirmed via the
rule's own `/api/prometheus/.../rules` status), widened to 3 minutes; and a plain wrong-port URL
(`https://` defaulting to 443 when Grafana's Service only listens on 80). Two of three real
drill runs in this pass genuinely failed to detect anything and left `t_detect` unset rather
than fabricated — the third succeeded with a 6-second detection latency. Also closed a
long-flagged gap: Grafana's ingress had zero Cilium restriction until this phase.

Unrelated finding, flagged not fixed: `measured_rpo_records_lost` came back strongly negative in
all three runs, violating the schema's own `minimum: 0` — a pre-existing bug in the ns-restore
workflow's counter-capture logic, spawned as its own follow-up task
(`task_a45b9f18`), out of this phase's scope.

Evidence: [`detection-latency-20260729135024.txt`](docs/evidence/samples/detection-latency-20260729135024.txt),
[`ns-restore-20260729135024.json`](docs/evidence/samples/ns-restore-20260729135024.json).

## Phase 11 — Incident response (in progress)

Closes out `drills/lib/classify.py` and `drills/lib/clocks.py`, both named in build-spec since
Phase 0 but never built. `classify.py` combines real measured fields (duration, data loss) with
a synthetic per-scenario severity profile (`classification-profiles.json`, reusing Meridian
Pay's established numbers) to approximate DORA's Art. 18 RTS classification logic — documented
as a simplification, not a verbatim transcription. `clocks.py` implements the exact
`t_notify_due_dora`/`t_notify_due_nis2` formulas from `docs/00-scope.md` §0.4, omitting both if
`t_detect` is missing rather than fabricating a basis. `drills/lib/enrich.py` runs this
host-side (not inside the workflow pod) and re-validates the result through `emit.py`'s own
schema check.

Original design used GitHub Issues for ticket delivery; mid-setup, the PAT-creation friction
prompted reconsidering *why* GitHub specifically — the honest answer was "zero new
infrastructure," not "the right tool." Pivoted to a real self-hosted ITSM tool instead: **GLPI**,
deployed on this same cluster (bare Deployment/Service/PVC for both GLPI and MariaDB — no
official Helm chart exists, same shape of problem OpenLDAP already hit; MariaDB uses the
official `mariadb` image, explicitly not `bitnami/mariadb`, whose free-tier images have moved to
an unmaintained "Legacy" repo — the same instability class already avoided for
`bitnami/openldap`). Still in progress — see `README.md`'s roadmap for current status.

## Follow-ups spawned, not yet resolved

- **`task_a45b9f18`** — `measured_rpo_records_lost` comes back negative in real drill runs, a
  pre-existing bug in the ns-restore workflow's counter-capture logic, unrelated to detection or
  incident-response work.
