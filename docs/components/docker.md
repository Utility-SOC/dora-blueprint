# Docker

> **In one sentence:** The tool that runs the lab's three 'servers' as containers on one machine, and runs the offline CA ceremony.

| | |
|---|---|
| **Category** | Cluster foundation |
| **Tier** | core |
| **Pinned version** | host-installed (not pinned by this repo) |
| **Where it lives** | [`bootstrap/install.sh`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/install.sh) |

## What it is, in plain English

Docker packages a program and everything it needs into a **container**: a lightweight, isolated process that behaves as if it had its own machine. Unlike a virtual machine it shares the host's kernel, so it starts in seconds and uses little memory overhead.

## Why it is here

Two jobs. First, Talos's Docker provisioner makes each cluster node a container, which is what lets the whole lab run on one laptop. Second, the offline Root CA ceremony runs inside a Docker container started with `--network none` (no network at all), standing in for an air-gapped machine ([runbook](../runbooks/pki-root-ca-issuance.md)).

## How this repository uses it

- `talosctl cluster create docker` creates one container per Talos node.
- The Root CA container `pki-root-ca` keeps the Root private key inside its own writable layer and is stopped, not deleted, afterwards.
- The `docker` group membership matters: shells opened before it was granted need `sg docker -c "..."`.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| ISO A.8.24; NIST SC-12 | Offline Root CA generation in a network-isolated container | [pki-chain-verification-20260729025500.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/pki-chain-verification-20260729025500.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

The lab's nodes disappear. Containers use `--restart=unless-stopped`, and a real `sudo reboot` test showed Docker brings all three nodes back without manual steps.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- A first attempt bind-mounted the Root CA private key into the 'isolated' container, leaving it in a host-readable directory the whole time. Fixed by keeping it inside the container's own layer.

## Limits and honest caveats

- A Root key inside a stopped Docker container is a lab substitute for a real offline ceremony (hardware token, separate machine, witnesses). The runbook says so.

## Official documentation

- [Docker documentation](https://docs.docker.com/)
- [Run containers with no network](https://docs.docker.com/engine/network/drivers/none/)
- [Restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/)

## Related pages

- [Talos Linux](talos.md)
- [cert-manager](cert-manager.md)
