# Kubernetes

> **In one sentence:** The system that decides which programs run on which machines and keeps them running.

| | |
|---|---|
| **Category** | Cluster foundation |
| **Tier** | core |
| **Pinned version** | v1.36.2 (set in `bootstrap/install.sh`) |
| **Where it lives** | [`bootstrap/install.sh`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/install.sh) |

## What it is, in plain English

Kubernetes (often written K8s) is software that manages a fleet of containers. You describe what you want ("run three copies of this program, give it this much memory, let it talk only to that database") and Kubernetes continuously works to make reality match. If a program crashes it restarts it; if a machine dies it moves the work elsewhere.

It organises work into **namespaces** (separate rooms), **pods** (one running program plus helpers), **deployments** (the description of how many copies), **services** (stable addresses), and **persistent volumes** (disks that outlive a pod). Almost everything in this repository is a Kubernetes object written as a YAML file.

## Why it is here

Kubernetes is the common substrate that the other tools plug into: the admission rules (Kyverno), network rules (Cilium), backup (Velero) and GitOps robot (Argo CD) all work by watching or controlling Kubernetes objects. It is also the thing regulators and auditors increasingly ask about, so a worked example of controlling it is useful in its own right.

## How this repository uses it

- The cluster is created by `bootstrap/install.sh` through Talos's Docker provisioner: one control-plane node (the brain) and two workers (where programs run).
- Cluster-wide Pod Security Standards are enforced by [Kyverno](kyverno.md), using Kubernetes's own built-in definition of "restricted".
- The **API server audit log** is shipped to [Loki](loki.md); one alert rule watches it for namespace deletions (this is how `t_detect` is measured).
- **Secrets encryption at rest** is a Talos default for the Kubernetes datastore, so it is deliberately not hand-configured.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9 | Pod Security Standards 'restricted' is the baseline that admission enforces | [kyverno-admission-20260728202845.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/kyverno-admission-20260728202845.txt) |
| DORA Art. 10; ISO A.8.16; NIST AU-2 | API audit logging gives detection something to observe | [detection-latency-20260729135024.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt) |
| NIST CM-7 | Least functionality via restricted pod settings | [kyverno-admission-20260728202845.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/kyverno-admission-20260728202845.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Everything stops. A single control-plane node means there is no spare brain: if it is lost the whole platform is down until rebuilt. This is why the 'control-plane loss' drill scenario is deliberately deferred ([limitations](../04-limitations.md)).

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The Docker provisioner's default 2 GiB per node starved `kube-controller-manager` into an hours-long crash loop that looked like a permissions bug until `docker stats` showed 93 % memory use. `install.sh` now sets explicit memory per node.
- Kubernetes's default 300-second toleration on 'unreachable' nodes meant a replacement pod landed straight back on the node the `node-kill` drill had tainted. Tainting alone does not keep pods away.

## Official documentation

- [Kubernetes documentation home](https://kubernetes.io/docs/home/)
- [Concepts overview](https://kubernetes.io/docs/concepts/overview/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)

## Related pages

- [Talos Linux](talos.md)
- [Kyverno](kyverno.md)
- [Cilium](cilium.md)
