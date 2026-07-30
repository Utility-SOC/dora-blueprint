# Exception: Tetragon (endpoint runtime security)

**Mechanism:** `exclude` block on the `restricted` rule in
`infrastructure/kyverno/policies/require-pod-security-restricted.yaml`, plus a native
Kubernetes PSS namespace label (`pod-security.kubernetes.io/enforce=privileged` on the
`tetragon` namespace) — same dual mechanism as `docs/exceptions/velero-node-agent.md`,
needed for the same reason: the *cluster's own built-in* PSS `baseline` admission
controller denies these pods independently of, and before, Kyverno ever evaluates them.
**Scope:** `Pod` resources in the `tetragon` namespace matching name `tetragon-*` — the
main DaemonSet only. The `tetragon-operator` Deployment runs fully `restricted`-compliant
(its one real gap, a missing `seccompProfile`, was fixed via chart config —
`tetragonOperator.podSecurityContext` in `apps/tetragon.yaml` — not folded into this
exception, since it had a real config-surface fix and the DaemonSet doesn't).
**Controls exempted:** all `restricted`-profile PSS controls (Privileged Containers, Host
Namespaces, HostPath Volumes, Running as Non-root, Capabilities, Seccomp) — for the
`tetragon-*` DaemonSet pods specifically.

## Why the exception exists

Confirmed live, not assumed: a real deploy attempt without any exception produced a real
admission denial from the *cluster's own built-in* PSS `baseline` controller (not Kyverno):

```
pods "tetragon-pf7vx" is forbidden: violates PodSecurity "baseline:latest": host
namespaces (hostNetwork=true), hostPath volumes (volumes "cilium-run", "tetragon-run",
"export-logs", "bpf-maps", "host-proc"), privileged (container "tetragon" must not set
securityContext.privileged=true)
```

`hostNetwork: true` and `privileged: true` are architecturally required for Tetragon's
core function — eBPF-based process visibility needs host-level kernel instrumentation, the
same class of requirement that already justified Cilium's own hostNetwork components being
excluded from PSS entirely (`infrastructure/cilium/kube-system/README.md`). There is no
`securityContext` configuration that gives a non-privileged, network-namespaced pod the
ability to load eBPF programs and observe every process on the node — same "no
config-surface workaround exists" bar every other exception in this repo is held to.

## Why this is a native PSS namespace label *and* a Kyverno exclude, not just one

Two independent admission mechanisms are in play here, confirmed by hitting both denials
live in sequence: the cluster's built-in PSS `baseline` controller (gated by the
`tetragon` namespace's own `pod-security.kubernetes.io/enforce` label, defaulting to
`baseline`) blocks the DaemonSet pods before Kyverno's webhook is even reached; separately,
Kyverno's own `require-pod-security-restricted` ClusterPolicy would deny the same pods
against `restricted` regardless of the namespace's native PSS label, since Kyverno
re-implements the PSS check itself rather than deferring to it. Both have to be addressed —
exactly the same two-layer pattern `velero`'s own node-agent exception already established
(`bootstrap/install.sh`'s `kubectl label namespace velero ...` step +
`docs/exceptions/velero-node-agent.md`), not a new pattern invented for this one.

## Compensating controls

- **Name-scoped, not namespace-wide**: the exclude matches `tetragon-*` specifically — the
  operator, sharing the `tetragon` namespace, needs no exception and runs fully
  `restricted`-compliant once its own real (and fixable) `seccompProfile` gap is closed via
  chart config.
- **Purpose-built namespace**: `tetragon` hosts only the Tetragon DaemonSet and its
  operator — no application workload shares this namespace.
- **RBAC-gated, not open access**: the DaemonSet's own ServiceAccount permissions
  (chart-managed) are scoped to what Tetragon's controllers/CRDs need, not general cluster
  admin.
- **No Cilium CNI policy applies here, stated plainly rather than silently absent**: a
  `hostNetwork: true` pod shares the node's own network identity — there is no per-pod
  CiliumNetworkPolicy endpoint for it to attach to, the same reason Cilium's own
  hostNetwork components are excluded from CNI segmentation entirely. Writing a policy
  that can't actually take effect would misrepresent enforcement that isn't real.
- **Read-only telemetry, not an enforcement point**: this deployment only observes and
  exports events (`export.mode: stdout`) — no `TracingPolicy` with `sigkill`/`override`
  enforcement actions is deployed, so a misconfiguration here can't itself kill or block a
  real workload.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see
`docs/04-limitations.md` on segregation of duties). Date: 2026-07-30. Reviewed alongside
Phase 13 (endpoint runtime security).
