# Exception: OpenLDAP (toy directory)

**Mechanism:** `exclude` block on the `restricted` rule in
`infrastructure/kyverno/policies/require-pod-security-restricted.yaml` — same mechanism
as the `alloy*` exception, not a `PolicyException` (see
`docs/exceptions/velero-node-agent.md` for why `PolicyException` is avoided for
pod-level violations in this repo — the same confirmed upstream Kyverno bug applies
here too, though it wasn't re-tested against this specific image since the alloy
precedent already established the working mechanism).
**Scope:** `Pod` resources in the `openldap` namespace matching name `openldap*`.
**Controls exempted:** all `restricted`-profile PSS controls (Running as Non-root,
Running as Non-root user, Capabilities, Privilege Escalation, Seccomp — no hostPath or
privileged access is actually used, unlike the Velero exception).

## Why the exception exists

`osixia/openldap:1.5.0`'s own "light baseimage" process-supervisor framework — not just
its LDAP-specific `chown` step — needs to run as root to function at all. Confirmed
directly, not assumed:

- Under `runAsNonRoot: true, runAsUser: 1000` (plus `allowPrivilegeEscalation: false`,
  capabilities dropped, `seccompProfile: RuntimeDefault`), the container printed exactly
  two log lines (`CONTAINER_LOG_LEVEL = 4 (debug)` then immediately `Killing all
  processes...`) and crash-looped — no application-level startup logic ever visibly ran.
- The same image, run directly via `docker run` as its own default user (root, no
  override) with the same `--loglevel debug`, produced a long, normal startup sequence:
  searching `/container/service`, linking startup scripts, dumping its environment,
  running the `:ssl-tools` and `slapd` startup stages in order.

The gap between "prints one debug line then dies" and "runs a full, verbose startup
sequence" is the framework's own bootstrap logic (symlinking into `/container/run/`,
processing environment files under `/container/environment/`), not anything specific to
this repo's LDAP configuration — a root cause outside what this repo's values/env can
work around, the same shape of "no supported config surface" finding as the Velero
exception, just for a different, smaller reason (a lightweight toy directory, not
Velero's architecturally-required host access).

## Compensating controls

- **No hostPath, no privileged access, no elevated capabilities actually used** — this
  exception grants PSS headroom the container's own startup framework needs, not a
  workload doing anything privileged with it. Contrast with the Velero exception, which
  exists because node-agent genuinely needs broad host filesystem access by design.
- **Purpose-built namespace**: `openldap` hosts only this one toy directory — no other
  workload shares the namespace, and the exclude is further scoped by name (`openldap*`)
  on top of the namespace match, matching the `alloy*` precedent rather than exempting
  the whole namespace unconditionally.
- **Not exposed to end users or client apps**: per the locked-in IAM design decision,
  LDAP traffic is exclusively Keycloak-to-OpenLDAP — no user or application ever talks
  to this pod directly, network-segmented the same way as every other namespace in
  Phase 6 (`infrastructure/cilium/openldap/`).
- **Ephemeral, re-seeded data, no persistent volume**: covered in
  `infrastructure/openldap/seed-ldif.yaml`'s own comment — this pod's entire directory
  contents are declared in git and rebuilt from nothing on every restart, so there's no
  standing state a root-level compromise of this specific container could persist
  beyond its own lifetime.

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see `docs/04-limitations.md`
on segregation of duties). Date: 2026-07-29. Reviewed alongside Phase 8 (IAM rollout).
