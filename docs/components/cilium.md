# Cilium (and Hubble)

> **In one sentence:** The network layer that blocks all traffic between parts of the platform unless a rule explicitly allows it.

| | |
|---|---|
| **Category** | Security enforcement |
| **Tier** | core |
| **Pinned version** | Cilium v1.19.6 (Helm, installed by `install.sh`) |
| **Where it lives** | [`infrastructure/cilium/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/cilium/), [`apps/core/cilium-policies.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/cilium-policies.yaml) |

## What it is, in plain English

Cilium is a **CNI** (container network interface): the plugin that gives pods network connectivity. It is built on **eBPF**, a Linux technology that runs small, verified programs inside the kernel, which makes it fast and lets it see traffic precisely. Cilium enforces **network policies**: written rules such as "the canary may talk to DNS and nothing else". **Hubble** is its observability part, showing every allowed or dropped connection.

## Why it is here

DORA Art. 9 asks for network design that limits contagion and can be segmented quickly. Default-deny with explicit allows is the standard technical answer. Using Hubble to observe real traffic *before* enforcing keeps the rules from breaking the platform.

## How this repository uses it

- Default-deny plus explicit allows in 8 platform namespaces (`canary`, `observability`, `velero`, `argo-workflows`, `openebs`, `local-path-storage`, `kyverno`, `argocd`), and more for `full`-tier namespaces.
- Each namespace followed the same loop: **audit mode**, a Hubble observation window, then enforcement, then a functional test.
- The `network-partition` drill applies and removes a real deny to prove enforcement in both directions.
- `kube-system` policies are applied by hand, not via Argo CD.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9(4)(b) | Network and infrastructure management with isolation | [cilium-network-segmentation-20260729015300.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/cilium-network-segmentation-20260729015300.txt) |
| ISO A.8.20, NIST SC-7 | Boundary protection through default-deny | [network-partition drill](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/scenario-breadth-20260730021814.txt) |
| DORA Art. 24-27 | A repeatable enforcement test, not a one-time snapshot | [scenario-breadth-20260730021814.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/scenario-breadth-20260730021814.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

If Cilium is down pods lose networking. If a policy is wrong, traffic breaks (a mistaken coredns rule briefly broke cluster DNS).

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- Cilium scopes an empty `fromEndpoints: [{}]` to the policy's **own namespace**, the same trap as Kubernetes `podSelector: {}`. It broke DNS, and the same mistake recurred twice more even after being documented.
- The Kyverno webhook call and the kubelet probe arrive as different Cilium identities (`remote-node` vs `host`) despite looking like one flow.
- `policy.cilium.io/audit-mode: "true"` is **not fully reliable** on this version: three policies enforced while annotated as audit-only. Treat it as advisory.
- `kubectl port-forward` bypasses Cilium enforcement on both ends, which is a documented gap.

## Limits and honest caveats

- `hostNetwork` pods (Cilium's own, Talos control-plane) are deliberately unsegmented.
- Eight namespaces are covered, not all of them.

## Official documentation

- [Cilium documentation](https://docs.cilium.io/en/stable/)
- [Network policy](https://docs.cilium.io/en/stable/security/policy/)
- [Hubble observability](https://docs.cilium.io/en/stable/observability/hubble/)
- [What is eBPF?](https://ebpf.io/what-is-ebpf/)
- [Policy audit mode](https://docs.cilium.io/en/stable/security/policy/intro/#policy-audit-mode)

## Related pages

- [Tetragon](tetragon.md)
- [Limitations](../04-limitations.md)
