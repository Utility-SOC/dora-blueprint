# Exception: OpenEBS localpv-provisioner helper pods

**PolicyException:** `infrastructure/kyverno/exceptions/openebs-localpv.yaml`
**Scope:** `Pod` resources named `init-pvc-*` or `cleanup-pvc-*` in the `openebs` namespace only.
**Controls exempted:** HostPath Volumes, Privileged Containers, Running as Non-root, Capabilities.

## Why the exception exists

`openebs-localpv-provisioner` exists specifically because `local-path-provisioner`'s
hostPath-typed PVs can't be backed up by Velero's File System Backup — see
`apps/openebs-localpv.yaml` for the full story of finding this out the hard way, and
`platform/talos/patches/common.yaml`'s `kubelet.extraMounts` entry it also required. Like
local-path-provisioner, it creates and removes the on-disk directory backing each PVC via a
short-lived helper pod with a hostPath mount — confirmed empirically (not assumed) by the exact
denial this exception clears: `pods "init-pvc-..." is forbidden: violates PodSecurity
"baseline:latest": hostPath volumes (volumes "data", "dev"), privileged (container
"local-path-init" must not set securityContext.privileged=true)`.

## Compensating controls

- **Scope**: exception matches only `init-pvc-*`/`cleanup-pvc-*` in the `openebs` namespace —
  the long-running `localpv-provisioner` controller pod itself is not exempted.
- **Purpose-built namespace**: `openebs` hosts only this provisioner. It backs exactly one
  volume in this cluster (the canary's PVC, `canary/pvc.yaml`) — everything else stays on
  `local-path-provisioner`.
- **Lifecycle**: helper pods are short-lived, created per PVC provision/delete and then removed.
- **This exception is in direct service of the project's core evidence chain**: the canary is
  the only volume Velero actually backs up and Phase 3's `ns-restore` drill actually restores —
  the same "the privilege is what makes the control real" reasoning as
  `docs/exceptions/velero-node-agent.md`.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see `docs/04-limitations.md` on
segregation of duties). Date: 2026-07-28. Reviewed alongside Phase 4 (Kyverno rollout).
