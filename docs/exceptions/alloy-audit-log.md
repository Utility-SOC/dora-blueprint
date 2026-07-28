# Exception: Alloy audit-log shipper

**PolicyException:** `infrastructure/kyverno/exceptions/alloy-audit-log.yaml`
**Scope:** `Pod` resources named `alloy-*` in the `observability` namespace.
**Controls exempted:** HostPath Volumes, Volume Types. Nothing else — Alloy runs as
non-root (uid 65534), with `allowPrivilegeEscalation: false` and all capabilities
dropped, so it's otherwise fully `restricted`-compliant.

## Why the exception exists

build-spec §12 Phase 4 requires "API audit logging shipping", not just an audit policy
that writes to a file no one reads. The kube-apiserver's audit log is a file
(`/var/log/audit/kube/kube-apiserver*.log` on the control-plane node), not container
stdout — confirmed directly, since Talos has no shell to check with, by mounting the
named Docker volume backing the controlplane container's `/var` into a throwaway `alpine`
container and running `ls`/`stat`/`tail` against it. `loki.source.kubernetes` (the
mechanism Alloy already used for every other pod's logs) reads via the Kubernetes API's
`pods/log` subresource and never touches the node filesystem, so it structurally cannot
see this file regardless of Alloy's placement or privileges. The only way to ship it is a
hostPath mount into whichever Alloy instance runs on that node.

## Why uid 65534, and why pinned to the control-plane node

Two details came from inspecting the real file rather than assuming:

- `stat` showed the audit log is `0600`, owned by uid/gid `65534` (Talos's own choice,
  not configured by this repo). Alloy's pod-level `securityContext` runs as that exact
  uid/gid — any other non-root uid would mount the hostPath fine and then get a
  permission-denied reading the file inside it.
- The file only exists on `resilience-lab-controlplane-1` (kube-apiserver's own node).
  Alloy's `controller.type` was already effectively single-instance (a `deployment` with
  `replicas: 1`); switching it to the chart's default `daemonset` *pinned to the
  control-plane node via `nodeSelector`* keeps that same one-instance behavior for pod-log
  collection (which reads via the API, so node placement doesn't matter for it) while
  putting that one instance on the only node where the audit-log hostPath resolves to
  something real.

## Compensating controls

- **Read-only mount**: the hostPath volume mount is `readOnly: true` — Alloy cannot write
  to or modify the audit log, only tail it.
- **Narrowest possible exemption**: only `HostPath Volumes` and `Volume Types` are
  exempted. Every other `restricted` control (non-root, no privilege escalation,
  capabilities dropped, seccomp) is enforced on this pod like any other — verified by
  the exception's own `podSecurity` list, which is two entries, not the full eight the
  Velero/OpenEBS exceptions carry.
- **Name-scoped, not namespace-wide**: unlike the Velero exception (which had to widen to
  the whole namespace after two narrower attempts failed against unpredictable ephemeral
  pod names), Alloy's DaemonSet pod names are chart-predictable (`alloy-*`), so the
  narrower name-glob match that failed for Velero works fine here.
- **Directory-scoped, not repo-root**: the mount is `/var/log/audit/kube`, not `/var/log`
  or `/var`, so it can't be used to read anything else on the host.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see `docs/04-limitations.md`
on segregation of duties). Date: 2026-07-28. Reviewed alongside Phase 4 (Kyverno rollout).
