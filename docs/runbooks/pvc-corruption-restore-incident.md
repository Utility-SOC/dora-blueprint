---
incident_type: silent-data-corruption
scenario: pvc-corruption-restore
controls: [DORA-Art11, DORA-Art12, DORA-Art18, DORA-Art19, NIS2-21.2.c, NIS2-Art23, ISO-A.8.13, ISO-A.5.29]
steps:
  - name: Inject the fault (corrupt the most recent row's hash in place, pod keeps running)
    automated: true
  - name: Detect via the drill's own explicit hash-chain integrity check
    automated: true
  - name: Delete the Deployment and its corrupted PVC
    automated: true
  - name: Restore Deployment+Pod+PVC from the most recent Velero backup, in the same namespace
    automated: true
  - name: Verify the restored hash chain and compute RTO/RPO
    automated: true
  - name: Classify the incident against DORA Art. 18 RTS criteria
    automated: true
  - name: Compute both DORA Art. 19 and NIS2 Art. 23 notification deadlines
    automated: true
  - name: Open a GLPI ticket with the classification, both deadlines, and a post-incident-review section
    automated: true
  - name: A human reviews the ticket, confirms the classification decision, and — only if actually major — performs the real regulatory notification (this repo cannot and does not file one)
    automated: false
  - name: A human closes the ticket once the post-incident review's manual-step gaps are addressed or explicitly accepted
    automated: false
---

# Runbook: silent data corruption → detect via hash chain → restore

## What this covers

The `pvc-corruption-restore` drill scenario (`drills/scenarios/pvc-corruption-restore.yaml`,
`drills/templates/pvc-corruption-restore-workflowtemplate.yaml`): the canary's data is corrupted
directly, in place, without touching the pod or namespace — the pod keeps running with silently
wrong data. This is exactly the failure mode build-spec §6.1 names as the reason the canary's
hash chain exists: "restore succeeded but the data is wrong" is a failure naive drills miss
entirely, because nothing about the pod, deployment, or namespace looks unhealthy.

## Real vs. synthetic inputs

The corruption (a real `UPDATE` against the live SQLite file), the detection (a real hash-chain
recompute), and the restore (a real Velero restore of the Deployment/Pod/PVC into the same
namespace) are all real, measured actions. No native CSI VolumeSnapshot support exists in this
lab's storage stack — see `docs/04-limitations.md` — so recovery uses Velero's own file-level
backup/restore, the same real mechanism `ns-restore` already relies on, rather than a snapshot
stack this lab doesn't have.

## Why the restore deletes the Deployment, not just the PVC

Velero's kopia/restic-based volume restore only repopulates data in the context of a *pod* being
restored (it injects a data-restore init container into pods that carry the right backup
annotation) — restoring a bare PVC object alone does not repopulate its data. The corrupted
Deployment is deleted first (cascading to its Pod) so the subsequent Velero restore can recreate
Deployment+Pod+PVC together without an existing, still-live ReplicaSet fighting for control of
the same pods.

## Why this drill has no `t_detect`

No independent alert exists in this lab for silent data-integrity faults yet — detection here is
the drill's own explicit `verify.py --field integrity_check` call, run against the still-running,
still-corrupted pod before any recovery action starts. Honestly recorded as the drill's own
detection, not an external signal, the same distinction `ns-restore`'s runbook draws for its own
Grafana-based detection.

## What still needs a human

Same as every scenario in this repo: the real regulatory notification, if the classification
were ever actually major, and the final review/close of the ticket.
