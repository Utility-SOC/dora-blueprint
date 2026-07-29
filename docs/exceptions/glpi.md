# Exception: GLPI (incident ticketing)

**Mechanism:** `exclude` block on the `restricted` rule in
`infrastructure/kyverno/policies/require-pod-security-restricted.yaml` — same mechanism
as the `alloy*`/`openldap*` exceptions, not a `PolicyException` (see
`docs/exceptions/velero-node-agent.md` for why `PolicyException` is avoided for
pod-level violations in this repo — the same confirmed upstream Kyverno bug applies).
**Scope:** `Pod` resources in the `glpi` namespace matching name `glpi-*` — scoped by
name specifically so MariaDB's pods in the same namespace (`mariadb-*`, which run fine
under `restricted`) stay fully governed by the cluster-wide policy.
**Controls exempted:** all `restricted`-profile PSS controls (Running as Non-root,
Running as Non-root user, Capabilities, Privilege Escalation, Seccomp).

## Why the exception exists

The official `glpi/glpi:10.0.18` image's own entrypoint script isn't executable by a
non-root user. Confirmed directly, not assumed:

- Under a full `restricted`-compliant `securityContext` (`runAsNonRoot: true,
  runAsUser: 1000`, `allowPrivilegeEscalation: false`, capabilities dropped,
  `seccompProfile: RuntimeDefault`), the container crash-looped immediately with
  `/usr/local/bin/docker-php-entrypoint: 9: exec: /opt/startup.sh: Permission denied`.
- `docker run --entrypoint sh glpi/glpi:10.0.18 -c 'ls -la /opt/startup.sh'` shows
  `-rwxr--r-- 1 root root ... /opt/startup.sh` — execute permission is set for the
  owner (root) only, not group or other. No `securityContext` short of running as root
  can exec a file with that permission bit — this isn't a `chown`/`fsGroup`-fixable
  ownership gap, the execute bit itself is absent for non-owner.

Same class of finding as the OpenLDAP exception (`docs/exceptions/openldap.md`): the
image's own bootstrap mechanism requires root to run at all, independent of anything
this repo's Deployment spec can configure around it.

## Compensating controls

- **No hostPath, no privileged access, no elevated capabilities actually used** — this
  exception grants PSS headroom the container's own entrypoint script needs to execute,
  not a workload doing anything privileged with that access.
- **Name-scoped, not namespace-wide**: the exclude matches `glpi-*` specifically:
  MariaDB, sharing the `glpi` namespace, needs no exception and remains fully
  `restricted`-compliant (`runAsNonRoot: true, runAsUser: 999`), confirmed by MariaDB
  reaching `1/1 Running` under the unmodified policy before GLPI's own root requirement
  was even investigated.
- **Network-segmented**: `infrastructure/cilium/glpi/` restricts GLPI's ingress to
  kubelet probes and the `argo-workflows` namespace (the drill's own ticket-creation
  calls) and MariaDB's ingress to GLPI only within the namespace, matching every other
  namespace's segmentation since Phase 6.
- **No SSO yet**: GLPI currently authenticates with its own local accounts (the
  auto-install default admin, changed via `configure-glpi.sh`), not OIDC through
  Keycloak — a real gap, not hidden; a future hardening pass could federate GLPI's own
  login the same way Argo CD/Grafana already are (Phase 8).

## Risk acceptance

Accepted by: the repository maintainer (single-operator lab — see
`docs/04-limitations.md` on segregation of duties). Date: 2026-07-29. Reviewed alongside
Phase 11 (Incident response).
