# Talos Linux

> **In one sentence:** A minimal operating system built only to run Kubernetes, with no shell and no SSH.

| | |
|---|---|
| **Category** | Cluster foundation |
| **Tier** | core |
| **Pinned version** | v1.13.7 |
| **Where it lives** | [`platform/talos/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/platform/talos/), [`bootstrap/install.sh`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/install.sh) |

## What it is, in plain English

A normal server runs a general-purpose operating system with a login shell, a package manager and hundreds of tools. **Talos Linux** removes all of that. Its root filesystem is read-only and signed, there is no `ssh`, no `bash`, and no way to install packages. The only way to manage a node is an authenticated API (`talosctl`). This sharply reduces what an attacker can use if they get in.

## Why it is here

It is a strong answer to hardening questions: fewer moving parts to patch, nothing to misconfigure by hand, and configuration expressed as files. It also forces honesty: you cannot run a host-compliance script on a Talos node because there is nowhere to run it. The repo reports that as an architectural fact and not as a failure ([host posture](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/host-posture-20260801015522.json)).

## How this repository uses it

- `bootstrap/install.sh` runs `talosctl cluster create docker`, which makes the nodes as Docker containers on one host. This is a lab stand-in for real VMs or bare metal.
- Node settings are patches: [`platform/talos/patches/common.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/platform/talos/patches/common.yaml) disables the built-in CNI (Cilium is installed instead), sets NTP servers, applies KSPP kernel hardening sysctls, and bind-mounts `/var/openebs/local` for local volumes.
- Talos nodes are **not** managed by [Argo CD](argo-cd.md); config changes need `talosctl apply-config`.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| ISO A.8.17 (clock synchronisation) | NTP servers configured so every RTO/RPO timestamp is trustworthy | [platform/talos patches](https://github.com/Utility-SOC/dora-blueprint/blob/main/platform/talos/patches/common.yaml). Clock-skew drill not yet built |
| NIST CM-6 | Immutable, API-only configuration | [host-posture-20260801015522.json](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/host-posture-20260801015522.json) |
| ISO A.8.9 (configuration management) | Node config is declarative patches in git | [platform/talos](https://github.com/Utility-SOC/dora-blueprint/tree/main/platform/talos) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Nodes cannot be managed, and the cluster cannot start or change. With no shell there is no emergency login: recovery is through `talosctl` or rebuilding.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- Talos has no chrony; time sync is a Talos setting, not a package.
- Kubernetes Secrets encryption at rest is a Talos default. Hand-configuring it crashes cluster creation.
- Talos's kubelet runs isolated; `local` volumes fail closed without an explicit bind mount.
- The Docker provisioner's 'nodes' are only as durable as the host: a host reboot is a simultaneous power cut for the whole cluster. A measured clean recovery took about 28 minutes.

## Limits and honest caveats

- The Docker provisioner is a lab convenience. A real deployment would use VMs or bare metal, which changes the failure model.
- Talos nodes cannot be queried for SELinux, AppArmor or FIPS status. The repo documents Talos's design instead.

## Official documentation

- [Talos documentation](https://docs.siderolabs.com/talos/latest/)
- [Talos in Docker](https://docs.siderolabs.com/talos/latest/platform-specific-installations/local-platforms/docker/)
- [Machine configuration patches](https://docs.siderolabs.com/talos/latest/configure-your-talos-cluster/system-configuration/patching)
- [talosctl reference](https://docs.siderolabs.com/talos/latest/reference/cli)

## Related pages

- [Kubernetes](kubernetes.md)
- [Docker](docker.md)
- [Limitations](../04-limitations.md)
