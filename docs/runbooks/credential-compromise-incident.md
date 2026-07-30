---
incident_type: runtime-detection-validation
scenario: credential-compromise
controls: [DORA-Art9, DORA-Art10, DORA-Art18, DORA-Art19, NIS2-21.2.c, NIS2-Art23, ISO-A.8.16]
steps:
  - name: Inject the fault (exec into canary-writer, read its ServiceAccount token, spawn /bin/sh)
    automated: true
  - name: Detect via Tetragon's real eBPF process-exec instrumentation and a Grafana Alerting rule
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

# Runbook: credential compromise → shell spawn → runtime detection

## What this covers

The `credential-compromise` drill scenario (`drills/scenarios/credential-compromise.yaml`,
`drills/templates/credential-compromise-workflowtemplate.yaml`, build-spec §6.3 scenario 8):
execs into `canary-writer` and reads its own mounted ServiceAccount token — the honest stand-in
for "an attacker who gained exec access is harvesting a real credential" — then spawns `/bin/sh`,
a real, anomalous process for a container that normally only ever runs `python3 writer.py`.
Build-spec's own framing: this "validates the runtime-detection path end to end," asserting not
merely "we detected it" but that the alert reaches the correct runbook (this one) within the
drill's own measured window.

## Real vs. synthetic inputs

The exec, the credential read, and the shell spawn are all real actions against the live cluster
— a real `execve` that Tetragon's eBPF instrumentation genuinely observes (build-spec Phase 13),
not a simulated log line. `t_detect` comes from a real Grafana Alerting rule
(`canary-shell-spawn-detect`) watching Loki for that exact real event, the same detection pattern
`ns-restore` already established in Phase 9, reused rather than a new parallel mechanism. Nothing
is actually broken by this drill — `canary-writer` stays healthy throughout, no data is at risk —
so unlike `ns-restore`/`node-kill`/`pvc-corruption-restore`, there's no "recovery" in the
break/fix sense; `measured_rto_seconds` doubles as detection latency (`t_detect` − `t_inject`),
the same shape `network-partition`'s own scenario already uses for a validation-only drill.

## Why this scenario has no custom eBPF policy

Tetragon observes every process execution by default (stock `process_exec` events) — no custom
`TracingPolicy` CRD was written for this. See `docs/exceptions/tetragon.md` for why Tetragon
itself needed a Kyverno PSS exception (`privileged: true` + `hostNetwork: true`, architecturally
required for eBPF process visibility) and how its ingestion into this repo's existing Loki
pipeline works (its own stdout-export sidecar, picked up by Alloy the same way every other pod's
stdout already is).

## Why every drill opens a ticket, not just "major" ones

Same reasoning as every other runbook in this repo: the ticket tracker is a timestamped incident
register, and a correctly non-major classification is itself useful evidence that the
classification logic works.

## What still needs a human

Same as every scenario in this repo: the real regulatory notification, if the classification
were ever actually major, and the final review/close of the ticket.
