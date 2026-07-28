# Exception: Velero node-agent (File System Backup)

**PolicyException:** `infrastructure/kyverno/exceptions/velero-node-agent.yaml`
**Scope:** `Pod` resources named `node-agent-*` in the `velero` namespace only.
**Controls exempted:** HostPath Volumes, Privileged Containers, Running as Non-root, Capabilities.

## Why the exception exists

Velero's node-agent DaemonSet is the mechanism this project relies on for actual PVC data
backup (build-spec §6.1's canary hash-chain writer, restored and verified in Phase 3's
`ns-restore` drill) — `local-path-provisioner`'s hostPath-backed volumes have no CSI snapshot
support, so File System Backup (kopia) is the only path to a restorable volume backup at all.
node-agent needs to read arbitrary pods' volume data via kubelet's host paths
(`/var/lib/kubelet/pods`, `/var/lib/kubelet/plugins`), which requires hostPath mounts and
privileged access by design — this is Velero's own documented architecture, not something this
repo configured more permissively than necessary.

## Compensating controls

- **Scope**: exception matches only `node-agent-*` in the `velero` namespace — the Velero
  server deployment itself, and everything else in the cluster, remains under the restricted
  profile.
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
