# OpenLDAP and LDAP Account Manager

> **In one sentence:** A directory of people and groups (the 'phone book' Keycloak reads), plus a web screen for editing it.

| | |
|---|---|
| **Category** | Identity |
| **Tier** | full |
| **Pinned version** | osixia/openldap image; LAM 8.3 |
| **Where it lives** | [`apps/full/openldap.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/openldap.yaml), [`apps/full/lam.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/lam.yaml), [`infrastructure/openldap/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/openldap/), [`infrastructure/lam/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/lam/) |

## What it is, in plain English

**LDAP** is a decades-old protocol for storing and querying a hierarchical directory of users, groups and attributes. **OpenLDAP** is the leading open-source server. **LDAP Account Manager (LAM)** is a web interface for adding users and groups so nobody edits raw LDAP.

## Why it is here

Enterprises commonly hold identities in a directory. Federating Keycloak to it shows the realistic pattern of an existing directory behind modern SSO.

## How this repository uses it

- Seeded with two toy users in two groups (`alice` in platform-admins, `bob` in platform-viewers), plus service groups for MinIO and GLPI created by `configure-service-groups.sh`.
- `onboard-user.sh` adds people. These scripts change only the **live** directory, so the seed file must be updated to match.
- Keycloak syncs groups into the `groups` claim; a full user sync is also required to reconcile existing members.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| ISO A.5.15-A.5.18; NIST AC-2 | Account and group management | [keycloak-ldap-oidc-verification-20260729043900.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Keycloak cannot look up new logins; already-issued tokens work until they expire.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The OpenLDAP image's init framework needs root; non-root prints one line and dies (confirmed by A/B test), hence the documented [exception](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/openldap.md).
- The seed script was not idempotent across restarts. A real PVC fixed it.
- `bitnami/openldap` no longer exists in Bitnami's free catalog, so a bare manifest with a community image is used.
- `configure-service-groups.sh` had a stray quote and did not even parse. The new test suite caught it.

## Limits and honest caveats

- `osixia/openldap` is a community image, not a vendor-supported product.

## Official documentation

- [OpenLDAP documentation](https://www.openldap.org/doc/)
- [osixia/openldap image](https://github.com/osixia/docker-openldap)
- [LDAP Account Manager docs](https://www.ldap-account-manager.org/lamcms/documentation)

## Related pages

- [Keycloak](keycloak.md)
