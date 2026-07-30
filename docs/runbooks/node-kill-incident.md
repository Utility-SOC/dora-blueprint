---
incident_type: node-unreachable
scenario: node-kill
controls: [DORA-Art11, DORA-Art18, DORA-Art19, NIS2-21.2.c, NIS2-Art23, ISO-A.8.13]
steps:
  - name: Inject the fault (taint the canary's node node.kubernetes.io/unreachable:NoExecute)
    automated: true
  - name: Force-delete the canary pod to compress the default 300s eviction grace period
    automated: true
  - name: Observe whether a replacement pod reaches Running while the node stays tainted
    automated: true
  - name: Remove the taint (recovery)
    automated: true
  - name: Verify the canary's hash chain and compute RTO once Ready again
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

# Runbook: worker node unreachable → taint, observe, recover

## What this covers

The `node-kill` drill scenario (`drills/scenarios/node-kill.yaml`,
`drills/templates/node-kill-workflowtemplate.yaml`): the worker node currently running the
canary tenant's workload is tainted `node.kubernetes.io/unreachable:NoExecute` — the exact taint
Kubernetes' own node-lifecycle-controller applies automatically on a genuinely unreachable node —
so this exercises the real eviction/reschedule control loop, not a synthetic stand-in.

## Real vs. synthetic inputs

The taint, the pod deletion, and the recovery are all real actions against the live cluster.
Whether the canary actually reschedules onto a different node while tainted, or sits unschedulable
until the taint is removed, is measured and recorded honestly — not asserted in advance.

**Observed live (drill_id `node-kill-20260730020314`):** the replacement pod reached `Running` on
the *same* tainted node within 15 seconds. This is real, correct Kubernetes behavior, not a drill
bug: pods get a default 300-second toleration against exactly this taint (the
`DefaultTolerationSeconds` admission plugin), and `canary`'s PV (`openebs-hostpath`) is node-local
and non-replicated, so the replacement pod had nowhere else it *could* schedule anyway. Tainting a
node alone, without also removing pods' default tolerations, does not by itself prevent a new pod
from returning to the tainted node — see `docs/04-limitations.md`. A future run could still
observe the "stuck Pending" outcome (e.g. if the default toleration window is exhausted before
recovery), so this section describes what happened, not a guarantee of what always will.

## Why this drill has no `t_detect`

Unlike `ns-restore` (Phase 9's Grafana Alerting rule watches for its specific fault signature),
no independent alert exists in this lab for a node going unreachable. `t_detect` is honestly
omitted rather than fabricated from the drill's own self-reported taint timestamp — the same
discipline `ns-restore` itself follows when its own detection genuinely fails.

## Why every drill opens a ticket, not just "major" ones

Same reasoning as `ns-restore-incident.md`: the ticket tracker is a timestamped incident
register, and a correctly non-major classification is itself useful evidence that the
classification logic works.

## What still needs a human

Same as every scenario in this repo: the real regulatory notification, if the classification
were ever actually major, and the final review/close of the ticket.
