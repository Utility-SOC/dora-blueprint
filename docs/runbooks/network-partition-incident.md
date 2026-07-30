---
incident_type: network-enforcement-validation
scenario: network-partition
controls: [DORA-Art9, ISO-A.8.20]
steps:
  - name: Confirm the target path is reachable before injecting anything (baseline)
    automated: true
  - name: Inject the fault (apply a drill-owned CiliumNetworkPolicy denying egress to observability)
    automated: true
  - name: Probe during the deny window, expecting failure
    automated: true
  - name: Remove the deny policy (recovery)
    automated: true
  - name: Probe after removal, expecting success
    automated: true
  - name: Classify the incident against DORA Art. 18 RTS criteria
    automated: true
  - name: Compute both DORA Art. 19 and NIS2 Art. 23 notification deadlines
    automated: true
  - name: Open a GLPI ticket with the classification, both deadlines, and a post-incident-review section
    automated: true
  - name: A human reviews the ticket and confirms the classification decision
    automated: false
  - name: A human closes the ticket once the post-incident review's manual-step gaps are addressed or explicitly accepted
    automated: false
---

# Runbook: network partition → validate Cilium enforcement, then recover

## What this covers

The `network-partition` drill scenario (`drills/scenarios/network-partition.yaml`,
`drills/templates/network-partition-workflowtemplate.yaml`): a temporary, drill-owned
`CiliumNetworkPolicy` denies this workflow pod's own egress to `observability` (Grafana) for a
bounded window, then is removed. Per build-spec §6.3, this scenario "doubles as validation that
the NetworkPolicies actually deny" — it turns Phase 6's one-time segmentation verification into a
real, repeatable drill rather than a snapshot taken once and never re-checked.

## Why this scenario looks different from the others

Unlike `ns-restore`/`node-kill`/`pvc-corruption-restore`, nothing here is actually broken or at
risk — no data, no workload availability. The "recovery" is simply removing a policy this same
drill created. `integrity_check` is set to `pass` unconditionally and documented as not
meaningful for this scenario shape, rather than contriving a fake check to satisfy the schema.

## Why `verdict` requires both a real failure and a real recovery

A drill that only checked "the policy object exists" would prove nothing — Cilium's `audit-mode`
annotation has already been found unreliable on this cluster's Cilium version
(`docs/04-limitations.md`), so this repo's own standing discipline is to verify enforcement
against real traffic, not a policy's declared intent. `verdict` is `pass` only if a live probe
against Grafana's Alerting API genuinely failed while the deny was in place, and a live probe
genuinely succeeded again once it was removed.

## Why this drill has no `t_detect`

No independent alert exists in this lab for Cilium enforcement events — the drill observes its
own injected fault directly, the same honesty discipline every other scenario in this repo
follows for a fault type with no configured detection signal yet.

## What still needs a human

Same as every scenario in this repo: reviewing the ticket, and the real regulatory notification
if the classification were ever actually major (unlikely for this scenario shape, but the same
pipeline runs regardless — see `docs/runbooks/ns-restore-incident.md` for why every drill opens a
ticket, not just "major" ones).
