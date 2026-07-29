# Platform / tenant shared-responsibility model

`docs/00-scope.md` §0.6 sketches the platform/tenant split as two short lists. This document
expands that into a control-by-control breakdown: for each control area, what the platform
guarantees identically regardless of which or how many tenants are onboarded, and what each
tenant must bring, configure, or decide for itself. The platform can't discharge a tenant's
own risk-assessment obligations by writing infrastructure code; it can only make the tenant's
job smaller and its evidence real.

Same discipline as `docs/03-control-matrix.md`: the **Evidence** column points at a generated
artifact or says `not yet generated`, never at a manifest describing intent. A control area
with nothing built yet is listed as such, not skipped — see §0.8/§0.9 below.

## Summary table

| Control area | Platform guarantees | Tenant must bring | Evidence |
|---|---|---|---|
| Network segmentation | Default-deny-first posture, explicit allows verified against real traffic in every onboarded namespace | A CiliumNetworkPolicy for any new tenant workload the platform doesn't already know about | [`cilium-network-segmentation-20260729015300.txt`](evidence/samples/cilium-network-segmentation-20260729015300.txt) |
| Admission control | Cluster-wide Pod Security Standards `restricted` enforcement, documented exception process | Compliant pod specs; a reviewed `PolicyException` for anything that can't comply | [`kyverno-admission-20260728202845.txt`](evidence/samples/kyverno-admission-20260728202845.txt) |
| Backup & recovery | Backup mechanism, Schedule infrastructure, proven restore path | Its own retention/RPO sizing, and which namespaces need a Schedule target | [`ns-restore-20260728204154.json`](evidence/samples/ns-restore-20260728204154.json) |
| Change management (GitOps) | Git-as-source-of-truth, automated drift correction, a destination allowlist bounding blast radius | Its own review/branch-protection discipline (organizational, not platform-enforced) | not yet generated — no CI evidence pipeline exists |
| Evidence & drill framework | Record schema, emitter, the ns-restore scenario | Additional scenarios specific to its own risk profile, once scenario breadth (Phase 10) lands | [`ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) |
| Cryptography (PKI) | Offline Root/Intermediate CA hierarchy, `ca`-type `ClusterIssuer` issuing real leaf certs | Request its own `Certificate` from `platform-ca` for any distinct hostname it needs | [`pki-chain-verification-20260729025500.txt`](evidence/samples/pki-chain-verification-20260729025500.txt) |
| Identity (IAM) | Nothing yet — not built | Not applicable until Phase 8 lands | not yet generated — Phase 8 |
| Detection (SIEM) | Nothing yet — not built | Not applicable until Phase 9 lands | not yet generated — Phase 9 |

## Network segmentation (Cilium)

**Platform guarantees:** every onboarded namespace gets a default-deny posture plus
narrowly-scoped explicit allows, and — critically — those allows are derived from real
observed traffic (Hubble, across every node agent, not from an architecture diagram) before
being written, then verified again after enforcement with an actual functional test specific
to that namespace (a backup, a sync, an admission-webhook round trip, a DNS lookup). All 8
namespaces in the platform's core stack are segmented this way as of this pass; see
`infrastructure/cilium/*/README.md` and file-level comments for the specific evidence behind
each namespace's rules.

The platform also guarantees an honestly-scoped exception list, not silence: `kube-system`'s
hostNetwork components (the CNI itself, the Talos control-plane static pods) are deliberately
**not** segmented and deliberately **not** Argo CD-managed — both boundaries are documented in
`infrastructure/cilium/kube-system/README.md`, discovered live rather than designed in advance
(a real Argo CD sync attempt surfaced that the `platform` AppProject's own destination
allowlist already excluded `kube-system`, which was then treated as correct and left in place).

**Tenant must bring:** a `CiliumNetworkPolicy` for any workload the platform doesn't already
have a policy for. The `canary` tenant namespace ships with a platform-provided
default-deny-all baseline (`infrastructure/cilium/canary/default-deny.yaml`), but if a tenant
adds a new component to its own namespace, writing that component's specific allow rules is
the tenant's job — the platform's segmentation work covers the platform's own namespaces, not
workloads a tenant introduces after onboarding.

## Admission control (Kyverno)

**Platform guarantees:** Pod Security Standards `restricted` enforced cluster-wide by
default (`failurePolicy: Fail` on the resource-validating webhook — confirmed, not assumed,
still enforcing correctly after `kyverno` and `argocd` were both network-segmented, see the
segmentation evidence file above), plus a documented, reviewed exception mechanism for the
small number of platform components that genuinely can't comply (`docs/exceptions/`).

**Tenant must bring:** pod specs that are PSS `restricted`-compliant from the start — the
platform does not (and by design should not) silently loosen this for a tenant. Anything that
can't comply needs its own reviewed `PolicyException`, following the same pattern as the
platform's own documented exceptions, not a platform-wide carve-out.

## Backup & recovery (Velero)

**Platform guarantees:** the backup mechanism itself (Velero + MinIO + node-agent FSB),
Schedule infrastructure, and a proven restore path — the `ns-restore` drill measures a real
RTO/RPO against a genuinely faulted namespace, not a clean-room restore. The mechanism also
survives network segmentation: a restored namespace carries the same default-deny-all policy
as the original (see the `canary-restored-*` entries in the segmentation evidence file above),
and Velero's own Kopia repository-maintenance path was found to have a real segmentation gap
mid-pass and fixed the same session (`infrastructure/cilium/velero/kopia-maintain-jobs.yaml`).

**Tenant must bring:** its own retention/RPO sizing from its own risk assessment. The
platform's current `ttl: 3h0m0s` is explicitly a lab disk-budget constraint, not a
compliance-appropriate value — see `docs/04-limitations.md`. A tenant must also declare which
of its namespaces need a `Schedule` target; the platform doesn't infer this automatically.

## Change management (GitOps / Argo CD)

**Platform guarantees:** git is the enforced source of truth (`prune: true, selfHeal: true` on
every platform Application), meaning drift from a manual `kubectl` change gets automatically
reverted — this was directly observed correcting the operator's own out-of-band edits during
this segmentation pass, not just a stated policy. The `platform` AppProject's `destinations`
field is an explicit namespace allowlist, not a wildcard, bounding how much of the cluster
GitOps automation can touch even if a commit is malicious or mistaken — `kube-system`'s
exclusion from that allowlist is the concrete example on record.

**Tenant must bring:** its own review and branch-protection discipline. This is organizational,
not something the platform's GitOps mechanics can enforce technically — flagged in
`docs/04-limitations.md`'s single-operator-lab caveat, since this lab has exactly one committer
and can't demonstrate segregation of duties regardless of what Argo CD's automation does.

## Evidence & drill framework

**Platform guarantees:** the drill record schema, the emitter, and the `ns-restore` scenario —
a real fault is injected, a real restore is measured, and the result is written as structured
evidence, not narrated after the fact.

**Tenant must bring:** additional drill scenarios specific to its own risk profile, once
scenario breadth work (build-spec Phase 10) lands. The platform demonstrates the pattern with
one scenario; it isn't a claim that one scenario is sufficient coverage for every tenant's risk
register.

## Cryptography (PKI) — built

**Platform guarantees:** a real offline-root/online-intermediate hierarchy (build-spec Phase 7),
not a flat `selfSigned` `ClusterIssuer`. The Root CA (10yr) never touches the cluster — it lives
in an isolated, shelved environment, generated and rotated per
`docs/runbooks/pki-root-ca-issuance.md`. The Intermediate CA (5yr, rotated at 4y11mo) does the
actual day-to-day leaf-cert issuance via a `ca`-type `ClusterIssuer`. Argo CD and Grafana both
serve real, cert-manager-issued TLS as of this phase — checked directly against the live served
certificate, not assumed from a `Certificate` resource's `Ready` status; see
[`pki-chain-verification-20260729025500.txt`](evidence/samples/pki-chain-verification-20260729025500.txt).

**Tenant must bring:** nothing extra to *use* this — any platform service gets a leaf cert from
the same `ClusterIssuer` for free. A tenant that needs its own distinct hostname/SAN set on a
cert would request its own `Certificate` resource referencing `platform-ca`, same pattern as
Argo CD/Grafana's.

## Identity and access management (IAM) — built

**Platform guarantees:** a self-hosted Keycloak IdP (build-spec Phase 8) federating from a toy
OpenLDAP directory (`infrastructure/openldap/`) — the pattern a regulated tenant's existing
AD/LDAP source of truth would plug into, rather than an IdP-native user database. Client apps
(Argo CD, Grafana) never see LDAP directly; they speak OIDC only, and Keycloak issues real ID
tokens with a `groups` claim populated from LDAP-federated group membership
(`infrastructure/keycloak/configure-realm.sh`). Both Argo CD and Grafana authenticate through
Keycloak's login page rather than a local password, and `argocd-rbac-cm`'s `policy.csv` maps
Keycloak groups to Argo CD roles (`platform-admins` → `role:admin`, `platform-viewers` →
`role:readonly`). This was verified as a live authorization decision — real ID tokens for two
LDAP-federated users, presented as Bearer credentials against Argo CD's own
`/api/v1/account/can-i/...` API — not inferred from `policy.csv`'s contents; see
[`keycloak-ldap-oidc-verification-20260729043900.txt`](evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt)
and
[`argocd-rbac-verification-20260729045300.txt`](evidence/samples/argocd-rbac-verification-20260729045300.txt).

**Tenant must bring:** its own group-to-role mapping if it needs roles beyond the two
demonstrated here (admin/read-only) — `policy.csv` entries and Keycloak group names are a
platform-provided pattern, not a fixed enumeration. A tenant onboarding its own application
behind OIDC would register a new Keycloak client and request the same `groups` protocol mapper
already wired for Argo CD/Grafana, rather than standing up a separate IdP.

**Explicitly still local, not platform-provided:** Argo CD and Grafana both keep their local
admin account active alongside OIDC SSO (deliberate — see build-spec Phase 8's own note on not
cutting over until OIDC is proven reliable across real logins); Keycloak itself runs against an
in-memory (`dev-mem`) database, so realm/client/federation config is durable only because it's
declared via `infrastructure/keycloak/configure-realm.sh` and re-applied, not because Keycloak's
own runtime state persists across a restart. A real deployment would run Keycloak against an
external Postgres for session/audit durability — stated plainly as a lab simplification, not
glossed over.

## Detection — built

**Platform guarantees:** a real Grafana Alerting rule (build-spec Phase 9), file-provisioned
the same declarative way as everything else in this repo, evaluating a LogQL query against the
kube-apiserver audit log (shipped to Loki since Phase 4 — no audit-policy change was needed).
This finalizes the Grafana-vs-Elastic technology trial in Grafana's favor: it was already deeply
integrated (real TLS from Phase 7, OIDC SSO from Phase 8, a live Loki datasource), and building
the platform's actual detection engine on top of it is what settled the comparison, rather than
standing up a second, parallel stack to re-litigate a decision Grafana had already earned. A
real `t_detect` — defined in build-spec as "first alert fired," not something a drill gets to
self-report — now exists for the first time: the ns-restore drill polls Grafana's own live
Alerting API immediately after fault injection and captures the alert's actual firing time, 6
seconds after injection in the verified run; see
[`detection-latency-20260729135024.txt`](evidence/samples/detection-latency-20260729135024.txt).
Two real detection failures surfaced and were fixed during verification (a query-format bug
rejected by Grafana's threshold expression, then a lookback window too tight for real
shipping+ingestion+evaluation latency) — both left `t_detect` honestly unset rather than
fabricated, consistent with this repo's "a drill that fails to detect is still valid evidence"
discipline.

**Tenant must bring:** its own detection rules for tenant-specific signals — the platform
provides the alerting engine and the pattern (a LogQL/PromQL condition, file-provisioned,
evaluated on a short interval with `for: 0s` so latency reflects real pipeline behavior rather
than an artificial debounce), not an exhaustive rule set for every tenant's own risk profile.

**Explicitly still missing:** evidence write-once/tamper-evidence guarantees (build-spec P7) —
today's evidence samples are plain git-tracked files, so git history is the only tamper-evidence
property they have; real ILM/write-only-ingest/object-locked-snapshot guarantees aren't built.
Notification delivery (a real webhook receiver, as opposed to Grafana's non-functional default
contact point) is deferred to build-spec Phase 11, where the same alert state this phase makes
queryable becomes the trigger for a real ticket in GLPI, this platform's self-hosted ITSM tool.
