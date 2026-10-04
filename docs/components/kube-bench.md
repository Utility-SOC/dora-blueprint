# kube-bench (planned)

> **In one sentence:** Would check the cluster against the CIS Kubernetes Benchmark; not built yet.

| | |
|---|---|
| **Category** | Planned, not built |
| **Tier** | not built |
| **Pinned version** | not deployed |
| **Where it lives** | [`BUILD-SPEC.md`](https://github.com/Utility-SOC/dora-blueprint/blob/main/BUILD-SPEC.md) |

## What it is, in plain English

The **CIS Benchmark** is a widely used checklist of secure Kubernetes settings. **kube-bench** runs the checks and reports pass, fail or warn.

## Why it is here

It would give DORA Art. 24-27 a configuration-baseline test result beyond the drills. It needs a live cluster to build and verify honestly, so it has not been done.

## How this repository uses it

- Listed under Phase 14 as still open.
- The control matrix marks the CIS output row as not yet generated.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 24-27; NIST CM-6 | Configuration baseline test | Not generated |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

n/a

## Limits and honest caveats

- Talos is not a conventional host, and some CIS node checks will not apply, which should be reported as 'not applicable'.

## Official documentation

- [kube-bench](https://github.com/aquasecurity/kube-bench)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

## Related pages

- [Gaps register](../compliance/gaps.md)
