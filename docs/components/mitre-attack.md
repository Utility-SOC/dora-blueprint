# MITRE ATT&CK

> **In one sentence:** A public catalogue of how real attackers behave, used here to label what each alert actually detects.

| | |
|---|---|
| **Category** | Evidence and compliance tooling |
| **Tier** | docs |
| **Pinned version** | technique IDs T1485, T1059.004 |
| **Where it lives** | [`docs/07-attack-mapping.md`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/07-attack-mapping.md), [`apps/core/grafana.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/grafana.yaml) |

## What it is, in plain English

**ATT&CK** lists attacker *tactics* (goals, like Execution or Impact) and *techniques* (methods, like 'Unix shell'). Mapping a detection to a technique says what class of attacker behaviour it would catch.

## Why it is here

'We have monitoring' is vague. 'This rule observes T1059.004 via eBPF process events' is checkable.

## How this repository uses it

- Two rules, two techniques: T1485 (Data Destruction) and T1059.004 (Unix Shell). Both are real Grafana annotations on the rules.
- The map is deliberately small: a technique appears only once a running detection observes it.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| NIST SI-4; DORA Art. 10 | Detection coverage expressed in a common vocabulary | [ATT&CK mapping](../07-attack-mapping.md) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Not a runtime component.

## Limits and honest caveats

- Two techniques is thin coverage. Do not read this as threat coverage.

## Official documentation

- [MITRE ATT&CK](https://attack.mitre.org/)
- [T1485 Data Destruction](https://attack.mitre.org/techniques/T1485/)
- [T1059.004 Unix Shell](https://attack.mitre.org/techniques/T1059/004/)

## Related pages

- [Grafana](grafana.md)
- [Tetragon](tetragon.md)
