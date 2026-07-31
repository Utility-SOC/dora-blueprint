# MITRE ATT&CK mapping

Every real detection this platform has (both live Grafana Alerting rules in
`apps/grafana.yaml`'s `detection` group) mapped to the ATT&CK technique it actually observes. Two
detections, two techniques — this is small on purpose: the point is that both are *real*,
eBPF/audit-log-observed detections tied to techniques they genuinely detect, not a padded list of
aspirational coverage.

| Detection rule | Technique | Tactic | Why |
|---|---|---|---|
| `canary-ns-delete-detect` | [T1485 — Data Destruction](https://attack.mitre.org/techniques/T1485/) | Impact (TA0040) | Observes a real `delete` verb against the canary namespace via the kube-apiserver audit log — the same fault `ns-restore`'s RPO measurement is built around. |
| `canary-shell-spawn-detect` | [T1059.004 — Command and Scripting Interpreter: Unix Shell](https://attack.mitre.org/techniques/T1059/004/) | Execution (TA0002) | Observes a real `/bin/sh`/`/bin/bash` `execve` inside the canary namespace via Tetragon's eBPF process-exec instrumentation — the `credential-compromise` scenario's fault injection. |

Both rules carry these as real Grafana annotations (`attack_technique`, `attack_tactic`), visible
on the alert itself, not just in this document — see `apps/grafana.yaml`. Evidence for both is
indexed under `docs/evidence/by-control/attack/` (`docs/evidence/manifest.yaml` +
`docs/evidence/collect.py`).

## Reading this table

- A technique only appears here once a real, running detection observes it — this is not a
  target-state coverage map of everything the platform *could* detect.
- As Phase 16 (security operations) and future scenario work land more detections, they get added
  here the same way: name the rule, name the technique, name the real telemetry that ties them
  together.
