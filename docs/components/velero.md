# Velero

> **In one sentence:** Takes scheduled backups of Kubernetes applications and their data, and restores them on demand.

| | |
|---|---|
| **Category** | Backup and storage |
| **Tier** | core |
| **Pinned version** | chart 12.1.0 (AWS plugin v1.14.2) |
| **Where it lives** | [`apps/core/velero.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/velero.yaml), [`infrastructure/velero/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/velero/) |

## What it is, in plain English

**Velero** backs up Kubernetes objects and, with **File System Backup** (using Kopia), the *contents* of volumes, to object storage ([MinIO](minio.md)). A **Schedule** makes backups automatic. A **Restore** recreates them, optionally into a differently-named namespace.

## Why it is here

Backup and restoration are explicit legal requirements (DORA Art. 12). The point here is not that backups exist but that a **restore was performed and timed**.

## How this repository uses it

- An hourly Schedule with a `ttl` of 3 hours (a lab disk constraint, not a policy).
- `deployNodeAgent: true`, because local volumes have no CSI snapshot support, so File System Backup is the only way to capture data.
- Restores always go to a *freshly named* namespace.
- Credentials come from an existing Secret created by `install.sh` from SOPS.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 11, 12; NIS2 21(2)(c); ISO A.8.13; NIST CP-9, CP-10 | Backup, restore, measured RTO and RPO | [ns-restore-20260728152755.json](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json) |
| DORA Art. 24-27; NIST CP-4 | Restore exercised repeatedly by drills | [scenario-breadth-20260730021814.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/scenario-breadth-20260730021814.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

No new backups, and restore drills fail. Existing backups in MinIO remain usable.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- **The most important bug in the project.** A full drill ran with zero errors and 'Completed' status but restored an *empty* volume, because Velero's File System Backup silently skips `hostPath` volumes. It was caught by inspecting the restored data. This is why the integrity check exists and why OpenEBS is used for the canary's volume.
- Kopia repository-maintenance CronJobs had been failing against MinIO unnoticed until the network-policy work exposed them.

## Limits and honest caveats

- **Retention is far too short for compliance** (3 h). Real deployments need tiered schedules sized from a risk-assessed RPO. The mechanism is demonstrated, not the number.
- Restores land on the **same cluster**. DORA Art. 12(3) asks for restoration onto segregated systems. See the [gaps register](../compliance/gaps.md).
- The 71-record RPO is bounded by an hourly schedule.

## Official documentation

- [Velero documentation](https://velero.io/docs/)
- [File System Backup](https://velero.io/docs/main/file-system-backup/)
- [Restore reference](https://velero.io/docs/main/restore-reference/)
- [Backup reference and schedules](https://velero.io/docs/main/backup-reference/)

## Related pages

- [MinIO](minio.md)
- [Storage provisioners](storage.md)
- [Canary](canary.md)
