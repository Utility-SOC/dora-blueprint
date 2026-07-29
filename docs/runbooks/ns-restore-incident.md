---
incident_type: namespace-deletion
scenario: ns-restore
controls: [DORA-Art11, DORA-Art12, DORA-Art18, DORA-Art19, NIS2-21.2.c, NIS2-Art23, ISO-A.8.13, ISO-A.5.29, ISO-A.8.16, DORA-Art10]
steps:
  - name: Inject the fault (delete the canary namespace)
    automated: true
  - name: Detect the fault via the kube-audit Loki stream and a real Grafana Alerting rule
    automated: true
  - name: Locate the most recent completed Velero backup
    automated: true
  - name: Restore into a freshly named namespace (never in place)
    automated: true
  - name: Verify the restored canary-writer's hash chain and compute RTO/RPO
    automated: true
  - name: Classify the incident against DORA Art. 18 RTS criteria
    automated: true
  - name: Compute both DORA Art. 19 and NIS2 Art. 23 notification deadlines
    automated: true
  - name: Open a GitHub Issue with the classification, both deadlines, and a post-incident-review section
    automated: true
  - name: A human reviews the issue, confirms the classification decision, and — only if actually major — performs the real regulatory notification (this repo cannot and does not file one)
    automated: false
  - name: A human closes the issue once the post-incident review's manual-step gaps are addressed or explicitly accepted
    automated: false
---

# Runbook: canary namespace deletion → restore, classify, notify

This is the first incident-response runbook in this repo's newer machine-readable-front-matter
shape (build-spec §6.8) — distinct from `docs/runbooks/pki-root-ca-issuance.md`'s narrative-only
style, which documents a one-off setup process rather than a repeatable incident response. The
front matter above is the actual step list `drills/lib/run-drill.sh` executes for this scenario,
each one honestly marked `automated: true` or `false` — not an aspirational description of what
a mature version of this pipeline *should* do.

## What this covers

The `ns-restore` drill scenario (`drills/scenarios/ns-restore.yaml`,
`drills/templates/ns-restore-workflowtemplate.yaml`): the canary tenant's namespace is deleted
outright, and the platform must detect, recover, classify, and report on that fault end to end,
with every timestamp in the resulting record either genuinely measured or explicitly derived
from a genuinely measured one — never fabricated.

## Real vs. synthetic inputs

Recovery (RTO, RPO, integrity) and detection (`t_detect`, via a real Grafana Alerting rule on
the kube-apiserver audit log) are fully real and measured against the live cluster. Classification
(`drills/lib/classify.py`) combines two real measured inputs (duration, data loss) with a
synthetic per-scenario severity profile (`drills/lib/classification-profiles.json`) for the
criteria a lab genuinely cannot measure (clients affected, geographical spread, economic impact,
reputational impact) — see that file's own comment, and `docs/04-limitations.md`, before treating
any classification decision from this runbook as more than a demonstration of the *logic*.

## Why every drill opens an issue, not just "major" ones

Per build-spec §6.8, "the issue tracker becomes a timestamped incident register." Gating issue
creation on the classification outcome would mean losing the record of *why* a non-major
incident was correctly judged non-major — which is itself useful evidence that the
classification logic works, not just a log of escalations.

## What still needs a human

Everything after the issue is opened. This repo does not, and should not, autonomously notify a
real regulator — DORA/NIS2 notification is a real legal act with real consequences, not
something a lab script should be able to trigger. The runbook's own front matter marks that step
`automated: false` deliberately, matching `manual_runbook_steps_required`'s existing role in
`drills/schema/drill-record.schema.json`: an honest count of what still needs a person is more
credible than claiming full automation.
