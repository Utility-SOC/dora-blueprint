# LDAP Account Manager

Requested directly: "I don't want to have to CLI to onboard every new user." A real GUI for
OpenLDAP user/group management (`ghcr.io/ldapaccountmanager/lam`), writing directly to the same
directory `infrastructure/openldap/onboard-user.sh` already wrote to via `ldapadd`/`ldappasswd`
— LAM doesn't replace anything about how Keycloak federates in, it's just a browser instead of a
CLI in front of the same directory.

## Login

- URL: `http://192.168.1.106:9086/` (once `bootstrap/port-forwards/lam.service` is installed)
- Server profile `lam` is auto-provisioned at first start (`LAM_SKIP_PRECONFIGURE=false` env)
  from this deployment's own env vars — no manual server-profile setup needed.
- Login DN: `cn=admin,dc=platform,dc=local` — same OpenLDAP admin credential already used
  everywhere else (`openldap-admin` Secret), not something LAM stores itself.
- LAM's own config UI (separate from the LDAP login above) is protected by a master password in
  the `lam-secrets` Secret (`lamMasterPassword`, sourced from `iam-secrets.enc.yaml` via
  `apply-secret.sh`) — you shouldn't need this unless changing the server profile itself.

## Relationship to Keycloak

Keycloak's LDAP federation is **read-only** (`infrastructure/keycloak/configure-realm.sh`,
`editMode: READ_ONLY`). Users/groups created or edited in LAM show up in Keycloak on that user's
next login (or the next scheduled federation sync) automatically — no extra step. Keycloak never
writes back to LDAP either way, so there's no conflict between the two.

Group membership alone doesn't invent new permissions — it only populates membership in roles
that already have a mapping in `argocd-rbac-cm`'s `policy.csv` (or Grafana's equivalent). Adding
someone to `platform-admins` in LAM gives them `role:admin` in Argo CD on their next login; adding
them to a brand-new group they made up doesn't do anything until that group is also mapped to a
role.

## Setup

```bash
bash infrastructure/lam/apply-secret.sh   # once, or after rotating iam-secrets.enc.yaml
bash bootstrap/port-forwards/install.sh   # picks up the new lam.service unit
```
