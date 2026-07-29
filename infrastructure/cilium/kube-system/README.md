# kube-system network segmentation scope

Eighth and final namespace in the confirmed segmentation order (canary ->
observability -> velero -> argo-workflows -> openebs/local-path-storage ->
kyverno -> argocd -> kube-system). This namespace is deliberately **partially**
segmented, not fully -- three of its workload kinds are explicitly excluded, for
reasons specific to what they are, not oversight.

## In scope (regular CNI-managed pods, policies in this directory)

- `coredns` -- serves DNS for the entire cluster
- `hubble-relay` -- aggregates flow data from every node's cilium-agent
- `hubble-ui` -- the Hubble UI's frontend/backend pod

## Explicitly out of scope

`kubectl -n kube-system get pods -o jsonpath='{.items[*].spec.hostNetwork}'`
confirms all of the following run with `hostNetwork: true`:

- `cilium-*` (cilium-agent DaemonSet), `cilium-envoy-*`, `cilium-operator-*`
- `kube-apiserver-*`, `kube-controller-manager-*`, `kube-scheduler-*` (Talos
  static control-plane pods)
- `kube-proxy-*`

Two independent reasons, either one sufficient on its own:

1. **hostNetwork pods share the node's own network namespace.** Cilium's
   identity-based policy model enforces per-CNI-endpoint, not per-hostNetwork-
   pod -- a CiliumNetworkPolicy `endpointSelector` matching, say,
   `kube-apiserver`'s pod labels would not cleanly isolate it from every other
   process sharing that same node's `host` identity the way it isolates actual
   CNI-managed pods from each other. It's not the right tool for this traffic
   shape.
2. **cilium-agent, cilium-envoy, and cilium-operator are the enforcement
   mechanism itself.** Writing CiliumNetworkPolicy that restricts the pods
   which *implement* CiliumNetworkPolicy is a well-known anti-pattern: get it
   wrong and there is no `kubectl` left to fix it with, since the CNI that
   `kubectl exec`/`apply` traffic depends on is what just broke. Given this
   lab has already found two confirmed instances of audit-mode not reliably
   staying non-enforcing on this Cilium version (see
   `infrastructure/cilium/observability/loki.yaml` and
   `infrastructure/cilium/openebs/provisioner.yaml`), the risk of a
   self-inflicted, unrecoverable networking outage here is judged to outweigh
   the marginal segmentation benefit. The control plane and CNI's own
   operational security is a different concern from workload-to-workload
   segmentation -- covered by RBAC, mTLS between components, and host-level
   access control, not overlay network policy.

This mirrors the general principle used throughout this pass (openebs's
unlabeled ephemeral pods, argocd-repo-server's un-pinnable GitHub/Helm egress):
segment what real evidence shows can be segmented safely, and document,
rather than silently omit, what's deliberately left alone.
