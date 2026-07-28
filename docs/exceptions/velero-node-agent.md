# Exception: Velero node-agent (File System Backup)

**Mechanism:** `exclude` block on the `restricted` rule in
`infrastructure/kyverno/policies/require-pod-security-restricted.yaml` — not a
PolicyException. See "Why this is a ClusterPolicy exclude, not a PolicyException" below
for why that changed partway through.
**Scope:** all `Pod` resources in the `velero` namespace. Widened from an initial
`node-agent-*` name match after a real drill run proved it insufficient — see below.
**Controls exempted:** all `restricted`-profile PSS controls, for every pod in this one
namespace (HostPath Volumes, Volume Types, Privileged Containers, Running as Non-root,
Running as Non-root user, Capabilities, Privilege Escalation, Seccomp).

## Why the exception exists

Velero's node-agent DaemonSet is the mechanism this project relies on for actual PVC data
backup (build-spec §6.1's canary hash-chain writer, restored and verified in Phase 3's
`ns-restore` drill) — `local-path-provisioner`'s hostPath-backed volumes have no CSI snapshot
support, so File System Backup (kopia) is the only path to a restorable volume backup at all.
node-agent needs to read arbitrary pods' volume data via kubelet's host paths
(`/var/lib/kubelet/pods`, `/var/lib/kubelet/plugins`), which requires hostPath mounts and
privileged access by design — this is Velero's own documented architecture, not something this
repo configured more permissively than necessary.

## Why the scope is namespace-wide, not name-matched

Two narrower attempts were tried first and both failed against a real `ns-restore` drill run,
not just in theory:

1. Matching `node-agent-*` by name misses the *ephemeral* per-backup/per-restore "hosting pods"
   kopia spins up to actually move volume data. These are named after the backup/restore itself
   (e.g. `canary-phase4-20260728163024-hlfgn`) — unpredictable by design, so a name glob can
   never reliably catch them.
2. Matching on Velero's own `velero.io/backup-name`/`velero.io/restore-name` labels also failed —
   those labels live on the `PodVolumeBackup`/`PodVolumeRestore` custom resource, not on the pod
   spec Velero actually submits for admission.

Both failures were caught the same way: `kubectl -n velero get backups.velero.io` showing
`PartiallyFailed`, checked directly rather than trusting a green status.

## Why this is a ClusterPolicy exclude, not a PolicyException

The namespace-wide fix above was first implemented as a `PolicyException` (the same mechanism
used by the other two exceptions in this repo), listing all eight `restricted` controls with
`controlName`/`images` entries. Every control worked *except* one: `Running as Non-root user`
kept blocking the kopia hosting pod on `spec.securityContext.runAsUser=0` no matter how the
exception was written. Four variants were tried and re-tested against a real backup each time,
all failing with the identical admission message:

1. Bare `controlName: Running as Non-root user` (no `images`).
2. `controlName: Running as Non-root user` with `images: ["*"]`.
3. Both of the above plus an explicit `restrictedField: spec.securityContext.runAsUser`
   (`values: ["0"]`) — targeting the exact pod-level path Kyverno's own error cited.
4. `restrictedField` redirected to the container-level path
   (`spec.containers[*].securityContext.runAsUser`) — the specific workaround documented against
   a near-identical bug report for the sibling `Running as Non-root` control.

All four were rejected identically. This matches a confirmed, still-open upstream bug —
[kyverno/kyverno#12888](https://github.com/kyverno/kyverno/issues/12888) — where a `podSecurity`
PolicyException fails to suppress a pod-level (not container-scoped) PSS violation, regardless of
`controlName`/`images`/`restrictedField` combination. It reproduces on Kyverno v1.18.2 (this
cluster's version), well past the version the issue was originally filed against, so it isn't a
version-skew problem this repo can sidestep by upgrading.

Velero's FSB hosting pod sets `runAsUser: 0` at the pod level with no supported config surface to
change it (checked the `node-agent-configmap` docs directly — no `securityContext` override
exists, only a blanket `privilegedFsBackup` toggle that doesn't touch `runAsUser`), so the pod
itself can't be made compliant either.

The fix: move this one namespace's exemption to a plain `exclude` block on the
`require-pod-security-restricted` ClusterPolicy's `restricted` rule
(`infrastructure/kyverno/policies/require-pod-security-restricted.yaml`), scoped to the `velero`
namespace — an older, simpler Kyverno mechanism not affected by the same bug. This is not a wider
grant than the PolicyException already committed to: both cover every `Pod` in the `velero`
namespace against every `restricted` control. Only the enforcement mechanism changed, because the
originally-intended one has a real bug blocking it for this specific field.

## Compensating controls

- **Scope**: exception matches every `Pod` in the `velero` namespace — a wider match than the
  other two exceptions in this repo, but not a wider *grant*: the namespace already carries a
  blanket native-PSS `privileged` override for the identical reason (see
  `bootstrap/install.sh`'s `kubectl label namespace velero ...` step), so this Kyverno exception
  doesn't permit anything the cluster wasn't already permitting — it makes Kyverno's own view
  consistent with that pre-existing reality instead of denying things natively-allowed pods.
- **Purpose-built namespace**: `velero` hosts only Velero and its in-cluster MinIO backend
  (`apps/minio.yaml`) — no application workload shares this namespace.
- **RBAC-gated, not open access**: node-agent's own ServiceAccount permissions (chart-managed)
  are scoped to backup/restore operations, not general cluster admin.
- **Evidence integrity note**: this is the exact mechanism the control matrix's DORA Art. 11/12
  and ISO A.8.13 rows point their evidence at (`docs/03-control-matrix.md`) — the privilege this
  exception grants is in direct service of a control this project measures, not incidental.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see `docs/04-limitations.md` on
segregation of duties). Date: 2026-07-28. Reviewed alongside Phase 4 (Kyverno rollout).
