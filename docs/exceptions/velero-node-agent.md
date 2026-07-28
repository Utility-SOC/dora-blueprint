# Exception: Velero node-agent (File System Backup)

**PolicyException:** `infrastructure/kyverno/exceptions/velero-node-agent.yaml`
**Scope:** all `Pod` resources in the `velero` namespace. Widened from an initial
`node-agent-*` name match after a real drill run proved it insufficient — see below.
**Controls exempted:** HostPath Volumes, Volume Types, Privileged Containers, Running as
Non-root, Running as Non-root user, Capabilities, Privilege Escalation, Seccomp.

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
