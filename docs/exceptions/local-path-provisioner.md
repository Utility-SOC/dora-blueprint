# Exception: local-path-provisioner helper pods

**PolicyException:** `infrastructure/kyverno/exceptions/local-path-provisioner.yaml`
**Scope:** `Pod` resources named `helper-pod-*` in the `local-path-storage` namespace only.
**Controls exempted:** HostPath Volumes, Privileged Containers, Running as Non-root, Capabilities.

## Why the exception exists

`local-path-provisioner` dynamically creates the on-disk directory backing each PVC by running
a short-lived helper pod that bind-mounts the host path and runs `mkdir`/`rm` against it. There
is no way to create or remove a directory on the node's filesystem without a container that can
see that filesystem — this is inherent to how the tool works, not a configuration choice that
could be tightened further. See `infrastructure/local-path-provisioner/kustomization.yaml` and
`platform/talos/README.md` for the storage design this supports.

## Compensating controls

- **Scope**: the exception matches only the `helper-pod-*` name pattern in the
  `local-path-storage` namespace — it does not weaken pod security anywhere else, and does not
  apply to the long-running `local-path-provisioner` controller pod itself, which runs under the
  restricted profile normally.
- **Namespace isolation**: `local-path-storage` hosts nothing except this provisioner. No
  application workload runs there, so a compromised helper pod's blast radius is the
  provisioner's own directory tree, not arbitrary application data.
- **Lifecycle**: helper pods are short-lived (created per PVC provision/delete, then removed),
  not standing infrastructure with a large attack window.
- **Used only for non-backed-up storage**: as of Phase 3, `local-path-provisioner` backs Loki
  and MinIO's volumes — neither is ever a Velero backup target, so this exception's blast radius
  doesn't extend into the evidence chain.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see `docs/04-limitations.md` on
segregation of duties). Date: 2026-07-28. Reviewed alongside Phase 4 (Kyverno rollout).
