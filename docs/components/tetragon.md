# Tetragon

> **In one sentence:** Watches what programs actually execute on the nodes, using eBPF, and reports it as logs.

| | |
|---|---|
| **Category** | Security enforcement |
| **Tier** | full |
| **Pinned version** | chart 1.7.0 |
| **Where it lives** | [`apps/full/tetragon.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/tetragon.yaml), [`docs/exceptions/tetragon.md`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/tetragon.md) |

## What it is, in plain English

Firewalls and admission rules govern what is *allowed*; **runtime security** watches what *happens*. **Tetragon** (from the Cilium project) uses **eBPF** to observe every process that starts (`execve`), network connection and file access, from inside the kernel, and emits structured events. An unexpected shell inside a container that should only run one Python program is exactly what it makes visible.

## Why it is here

DORA Art. 10 requires detection mechanisms with 'multiple layers of control'. The audit log is one layer (API activity); Tetragon is a second (what runs on the machines). It was chosen over Elastic Defend because the host's RAM was tight, and it reuses the existing log pipeline with no new shipping config.

## How this repository uses it

- Stock `process_exec` events stream as JSON to stdout; [Alloy](alloy.md) ships them to [Loki](loki.md).
- A Grafana alert, `canary-shell-spawn-detect`, fires on a shell binary executed in the `canary` namespace.
- The `credential-compromise` drill harvests the canary's ServiceAccount token and spawns `/bin/sh`: a real anomalous process.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 10; ISO A.8.16; NIST SI-4 | Endpoint runtime monitoring with an alert | [credential-compromise-20260730044858.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/credential-compromise-20260730044858.txt) |
| NIST IR-4 | Detection feeds incident handling | [incident-response-20260729210627.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/incident-response-20260729210627.txt) |
| MITRE ATT&CK T1059.004 | Unix shell execution detected | [ATT&CK mapping](../07-attack-mapping.md) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Process-level visibility is lost; the audit-log detection layer still works.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The DaemonSet needs `hostNetwork`, `privileged` and hostPath access (inherent to eBPF), so it is a documented Kyverno exception, not a hidden one ([exception](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/tetragon.md)).
- The operator hit a separate denial for a missing `seccompProfile`, which had a real chart-level fix and so was **not** folded into the exception.

## Limits and honest caveats

- Only one detection rule consumes these events today, so coverage is narrow by design.

## Official documentation

- [Tetragon documentation](https://tetragon.io/docs/)
- [Process execution events](https://tetragon.io/docs/concepts/events/)
- [What is eBPF?](https://ebpf.io/what-is-ebpf/)
- [ATT&CK T1059.004](https://attack.mitre.org/techniques/T1059/004/)

## Related pages

- [Grafana](grafana.md)
- [Loki](loki.md)
- [Cilium](cilium.md)
