# MinIO

> **In one sentence:** An in-cluster, Amazon-S3-compatible object store that holds the backups.

| | |
|---|---|
| **Category** | Backup and storage |
| **Tier** | core |
| **Pinned version** | chart 5.4.0, image pinned by digest (RELEASE.2025-09-07T16-13-09Z) |
| **Where it lives** | [`apps/core/minio.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/minio.yaml), [`infrastructure/velero/secrets/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/velero/secrets/) |

## What it is, in plain English

**Object storage** keeps files as named blobs behind an HTTP API, popularised by Amazon S3. **MinIO** provides the same API on your own hardware, so Velero can back up without any cloud account.

## Why it is here

The lab needs a backup target that works offline. S3-compatible storage is also what Velero expects.

## How this repository uses it

- Single node, in the `velero` namespace, root credentials from SOPS.
- The image is pinned by **digest** as well as tag, because the upstream registry is effectively frozen.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 12; ISO A.8.13; NIST CP-9 | Backup storage target | [ns-restore-20260728152755.json](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json) |
| NIST MP-6 (media sanitisation) | Retention and deletion policy | Not yet generated |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Backups cannot be written or read, and restores fail.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- MinIO ended community-edition image publishing around October 2025. The newest GitHub release tag was never pushed to Docker Hub, so the pin is the last real image.

## Limits and honest caveats

- **Supply-chain risk:** a frozen community image will not receive security fixes. Plan a migration (a maintained S3-compatible store, or a cloud bucket).
- Single node, no replication, no object lock yet. Object lock is noted as a possible second tamper-evidence mechanism.

## Official documentation

- [MinIO documentation](https://docs.min.io/community/minio-object-store/)
- [Amazon S3 API overview](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)

## Related pages

- [Velero](velero.md)
