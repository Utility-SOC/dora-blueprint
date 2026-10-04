# Keycloak (and PostgreSQL)

> **In one sentence:** The single sign-on server: log in once, and every connected tool knows who you are and which groups you belong to.

| | |
|---|---|
| **Category** | Identity |
| **Tier** | full |
| **Pinned version** | chart keycloakx 7.2.2; PostgreSQL 16 (alpine image) |
| **Where it lives** | [`apps/full/keycloak.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/keycloak.yaml), [`apps/full/keycloak-postgres.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/full/keycloak-postgres.yaml), [`infrastructure/keycloak/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/keycloak/) |

## What it is, in plain English

**Single sign-on (SSO)** means one login for many tools. **OpenID Connect (OIDC)** is the standard protocol: a tool (Argo CD, Grafana) redirects you to the **identity provider**, you authenticate, and it returns a signed token naming you and your **groups**. The tool maps groups to roles (admin, read-only). **Keycloak** is the open-source identity provider used here.

## Why it is here

Access control is a core requirement (DORA Art. 9(4)(c)-(d), NIS2 21(2)(i)-(j), ISO A.5.15-A.5.18). SSO centralises it: add a person to a group once and their access in every tool follows; remove them and it all goes.

## How this repository uses it

- Realm `platform`, federated to [OpenLDAP](openldap-lam.md) for users and groups, scripted with `configure-realm.sh` (`kcadm.sh`) rather than a hand-written export, because LDAP federation config is fragile to author by hand.
- Argo CD and Grafana accept OIDC logins and map the `groups` claim to roles. Local admin accounts are kept alongside, deliberately.
- PostgreSQL stores Keycloak's data. It began as in-memory H2, and a pod restart showed every realm and user vanished, so persistence was added and verified by actually restarting the pod.
- Operator credentials are scripted from the SOPS secrets (`persist-operator-credentials.sh`).

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| ISO A.5.15-A.5.18, A.8.2; NIST AC-2, IA-2 | Federated accounts and OIDC authentication | [keycloak-ldap-oidc-verification-20260729043900.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt) |
| NIST AC-3; DORA Art. 9(4)(c) | A real API authorization decision distinguishing admin from read-only | [argocd-rbac-verification-20260729045300.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/argocd-rbac-verification-20260729045300.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

SSO logins stop. Local admin accounts still work (kept for this reason).

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- Crash-looped three ways: a `startupProbe` override in the wrong shape, missing `securityContext` fields, and no default start command.
- `parent=` in a components lookup means the parent component's **id**, not the realm name. The create succeeded and the lookup silently matched nothing.
- A requestable `groups` scope must be a **client scope**, not only a per-client mapper (`invalid_scope: groups` otherwise).

## Limits and honest caveats

- Verification used real OIDC ID tokens against Argo CD's API, not a browser login (the automation environment could not drive one). The server-side checks are identical.
- Two toy users (`alice`, `bob`) exist; no real identity lifecycle, no multi-factor authentication configured.

## Official documentation

- [Keycloak documentation](https://www.keycloak.org/documentation)
- [Server administration](https://www.keycloak.org/docs/latest/server_admin/)
- [OpenID Connect explained](https://openid.net/developers/how-connect-works/)
- [keycloakx Helm chart](https://github.com/codecentric/helm-charts/tree/master/charts/keycloakx)
- [PostgreSQL documentation](https://www.postgresql.org/docs/)

## Related pages

- [OpenLDAP and LAM](openldap-lam.md)
- [Argo CD](argo-cd.md)
- [Grafana](grafana.md)
