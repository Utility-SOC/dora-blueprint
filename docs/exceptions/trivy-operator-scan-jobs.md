# Exception: Trivy Operator vulnerability-scan jobs

**PolicyException:** `infrastructure/kyverno/exceptions/trivy-operator-scan-jobs.yaml`
**Scope:** `Pod` resources named `scan-vulnerabilityreport-*` in the `trivy-system` namespace only.
**Controls exempted:** Running as Non-root, Seccomp. (Privileged, HostPath, and Capabilities are
already fine per the chart's real defaults — not exempted, not needed.)

## Why the exception exists

Trivy Operator's `scan-vulnerabilityreport-*` jobs are multi-container: one initContainer plus
three scanner containers combined into a single pod. The Helm chart's own
`scanJobPodTemplateContainerSecurityContext` value (set in `apps/trivy-operator.yaml`, and
correctly applied — confirmed by checking the deployed ConfigMap) only reaches one container
role in that pod, not all four. Confirmed empirically (not assumed) by the exact real denial this
exception clears: `spec.containers[0/1/2].securityContext.runAsNonRoot: Required value`,
`spec.initContainers[0]/containers[0/1/2].securityContext.seccompProfile.type: Required value` —
every container in the pod, on every real attempt, not a hypothetical.

Before this was caught, the resulting continuous create-then-reject loop (Kyverno rejecting the
same job spec every few seconds, forever) was the real root cause behind a separate resilience
incident — see `CHANGELOG.md`'s "Resilience pass" entry — so this isn't just a scanning-feature
gap, leaving it unresolved has a real operational cost.

## Compensating controls

- **Scope**: exception matches only the `scan-vulnerabilityreport-*` name pattern in the
  `trivy-system` namespace — the long-running `trivy-operator` controller pod itself is not
  exempted (it already runs fully PSS-restricted-compliant, confirmed).
- **Purpose-built namespace**: `trivy-system` hosts only Trivy Operator and its own scan jobs.
- **Lifecycle**: scan jobs are short-lived (minutes), created per scheduled/triggered scan and
  cleaned up afterward — not standing attack surface.
- **Narrow control list**: only the two controls the real denial actually names are exempted, not
  the whole `restricted` profile — Privileged Containers, HostPath Volumes, and Capabilities stay
  enforced on these pods.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see `docs/04-limitations.md` on
segregation of duties). Date: 2026-08-01. Applied during a resilience pass that also traced this
exact retry loop to real kube-proxy churn.
