# Kyverno

> **In one sentence:** The gatekeeper that inspects every new workload and refuses insecure ones before they start.

| | |
|---|---|
| **Category** | Security enforcement |
| **Tier** | core |
| **Pinned version** | chart 3.8.2 |
| **Where it lives** | [`infrastructure/kyverno/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/kyverno/), [`apps/core/kyverno.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/kyverno.yaml), [`apps/core/kyverno-policies.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/kyverno-policies.yaml), [`docs/exceptions/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/) |

## What it is, in plain English

Kubernetes has an **admission** step: before an object is saved, webhooks may inspect and reject it. **Kyverno** is a policy engine plugged into that step. Policies are Kubernetes YAML (no new language). If a workload would run as root, ask for full host access, or lacks required settings, it is denied with a readable reason.

## Why it is here

DORA Art. 9 asks for protection by design, and an auditor will ask "what *prevents* an insecure workload?". Kyverno gives a concrete answer, and the denial of a real privileged pod is saved as evidence.

## How this repository uses it

- `require-pod-security-restricted.yaml` enforces the Kubernetes **Pod Security Standards 'restricted'** profile cluster-wide, in `Enforce` mode from day one.
- `verify-image-signatures.yaml` requires the repo's own `canary-writer` image to carry a valid [cosign](sigstore-cosign.md) signature and SBOM attestation from the exact CI workflow identity, pinned by digest, no `:latest`.
- Anything that cannot comply gets a written exception in `docs/exceptions/<name>.md` before it is added to the policy (eight exist).
- `PolicyException` objects may only be created in the `kyverno` namespace, so tenants cannot exempt themselves.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9(4) | Prevention through enforced security baseline | [kyverno-admission-20260728202845.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/kyverno-admission-20260728202845.txt) |
| NIST CM-7; ISO A.8.9 | Least functionality; configuration baseline | [kyverno-admission-20260728202845.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/kyverno-admission-20260728202845.txt) |
| DORA Art. 28-30; NIST SR-3 | Only signed images from the expected build are admitted (for the repo's own image) | [credential-compromise-20260730044858.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/credential-compromise-20260730044858.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

The webhook uses `failurePolicy: Fail`, so if Kyverno is down new pods may be refused. That is secure but can block recovery, which is why its network policy was the highest-risk step.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- A `podSecurity` PolicyException cannot suppress a pod-level violation (kyverno issue #12888), so two exceptions are `exclude` blocks instead.
- Argo Workflows' injected init and wait containers had no `securityContext`, and the fix was in the chart config, not the workflow.
- GLPI's image cannot run under 'restricted', so the exclusion is scoped to `glpi-*` pods only. Tetragon needed the same for eBPF.

## Limits and honest caveats

- Image signature checks apply only to the repo's own image. Third-party images are not signed by their vendors in a way this repo checks, as the Register of Information states.

## Official documentation

- [Kyverno documentation](https://kyverno.io/docs/)
- [Validate rules](https://kyverno.io/docs/policy-types/cluster-policy/validate/)
- [Pod Security Standards policies](https://kyverno.io/policies/?policytypes=Pod+Security+Standards+%28Restricted%29)
- [Policy exceptions](https://kyverno.io/docs/exceptions/)
- [Verify images](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/)

## Related pages

- [Cilium](cilium.md)
- [Sigstore and cosign](sigstore-cosign.md)
- [Exceptions folder](https://github.com/Utility-SOC/dora-blueprint/tree/main/docs/exceptions)
