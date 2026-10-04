# Storage provisioners (local-path and OpenEBS LocalPV)

> **In one sentence:** Hand out disk space to applications that ask for it; two are used because only one kind can be backed up.

| | |
|---|---|
| **Category** | Backup and storage |
| **Tier** | core |
| **Pinned version** | OpenEBS chart 3.10.0; local-path-provisioner (manifests) |
| **Where it lives** | [`apps/core/local-path-provisioner.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/local-path-provisioner.yaml), [`apps/core/openebs-localpv.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/openebs-localpv.yaml), [`infrastructure/local-path-provisioner/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/local-path-provisioner/) |

## What it is, in plain English

A **PersistentVolumeClaim** is an application's request for disk. A **provisioner** creates the disk. Talos ships none, so two lightweight ones are added: `local-path-provisioner` (volumes are plain directories, `hostPath` type) and OpenEBS LocalPV (volumes are `local` type).

## Why it is here

This split is the direct result of the key Velero finding above: Velero File System Backup supports `local` volumes but silently skips `hostPath` ones. Loki and MinIO never need restoring so use the simple one; the canary needs real backups so uses OpenEBS.

## How this repository uses it

- `local-path-provisioner` is the default StorageClass for Loki, MinIO, Grafana and others.
- OpenEBS LocalPV (`openebs-hostpath`) backs only the canary's data volume, with a Talos kubelet bind mount for `/var/openebs/local`.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 12; NIST CP-9 | Makes the canary's data actually backed up | [ns-restore-20260728152755.json](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

New volumes cannot be created. Existing ones stay.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- See [Velero](velero.md): the empty-restore bug.
- OpenEBS tried to send telemetry to Google, and an egress allow-rule had to be reasoned about (documented in the Cilium findings).

## Limits and honest caveats

- Local volumes live on one node. They are not replicated, so the canary's volume pins it to a node (which also shaped the `node-kill` findings).

## Official documentation

- [OpenEBS documentation](https://openebs.io/docs)
- [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
- [Kubernetes volumes (local vs hostPath)](https://kubernetes.io/docs/concepts/storage/volumes/#local)

## Related pages

- [Velero](velero.md)
- [Canary](canary.md)
