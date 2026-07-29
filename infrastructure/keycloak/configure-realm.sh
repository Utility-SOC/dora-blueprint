#!/usr/bin/env bash
# Phase 8 (IAM): scripted realm setup, run against the live Keycloak admin API via
# kcadm.sh (bundled in the pod itself) -- NOT a hand-written realm-export JSON. Modern
# Keycloak's LDAP-federation config uses a verbose, component-based schema that's much
# more reliable to build via the same tool Keycloak's own admin console uses internally
# than to guess at by hand; every step here was run for real against the actual running
# instance and independently verified (querying synced users/groups, decoding a real
# access token to confirm the `groups` claim) before being written down, not the other
# way around.
#
# Idempotent-ish: `kcadm.sh create` will fail loudly on a resource that already exists
# rather than silently doing nothing -- acceptable for this repo's single-run bootstrap
# pattern (matching bootstrap/install.sh's own "already exists, skipping" checks
# elsewhere), not retried automatically here. Re-running against an already-configured
# realm needs the realm deleted first (`kcadm.sh delete realms/platform`), since
# database.vendor: dev-mem means the realm doesn't survive a pod restart anyway.
set -euo pipefail

KC_POD="${KC_POD:-keycloak-keycloakx-0}"
KC_NS="${KC_NS:-keycloak}"
KCADM="kubectl -n $KC_NS exec $KC_POD -- /opt/keycloak/bin/kcadm.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> [1/6] Login as bootstrap admin"
KC_ADMIN_PW="$(kubectl -n "$KC_NS" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
$KCADM config credentials --server http://localhost:8080/auth --realm master --user admin --password "$KC_ADMIN_PW"

echo "==> [2/6] Create the platform realm"
$KCADM create realms -s realm=platform -s enabled=true

echo "==> [3/6] LDAP user federation, pointing at the toy OpenLDAP directory"
LDAP_BIND_PW="$(kubectl -n "$KC_NS" get secret iam-secrets -o jsonpath='{.data.ldapBindPassword}' | base64 -d)"
$KCADM create components -r platform \
  -s name=openldap \
  -s providerId=ldap \
  -s providerType=org.keycloak.storage.UserStorageProvider \
  -s 'config.enabled=["true"]' \
  -s 'config.priority=["1"]' \
  -s 'config.editMode=["READ_ONLY"]' \
  -s 'config.syncRegistrations=["false"]' \
  -s 'config.vendor=["other"]' \
  -s 'config.usernameLDAPAttribute=["uid"]' \
  -s 'config.rdnLDAPAttribute=["cn"]' \
  -s 'config.uuidLDAPAttribute=["entryUUID"]' \
  -s 'config.userObjectClasses=["inetOrgPerson"]' \
  -s 'config.connectionUrl=["ldap://openldap.openldap.svc.cluster.local:389"]' \
  -s 'config.usersDn=["ou=people,dc=platform,dc=local"]' \
  -s 'config.authType=["simple"]' \
  -s "config.bindDn=[\"cn=admin,dc=platform,dc=local\"]" \
  -s "config.bindCredential=[\"$LDAP_BIND_PW\"]" \
  -s 'config.pagination=["true"]' \
  -s 'config.importEnabled=["true"]'

LDAP_COMPONENT_ID="$($KCADM get components -r platform -q name=openldap --fields id --format csv --noquotes)"
$KCADM create "user-storage/$LDAP_COMPONENT_ID/sync?action=triggerFullSync" -r platform

echo "==> [4/6] LDAP group federation (groupOfNames -> Keycloak groups)"
$KCADM create components -r platform \
  -s name=ldap-groups \
  -s providerId=group-ldap-mapper \
  -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
  -s "parentId=$LDAP_COMPONENT_ID" \
  -s 'config."groups.dn"=["ou=groups,dc=platform,dc=local"]' \
  -s 'config."group.name.ldap.attribute"=["cn"]' \
  -s 'config."group.object.classes"=["groupOfNames"]' \
  -s 'config."membership.ldap.attribute"=["member"]' \
  -s 'config."membership.attribute.type"=["DN"]' \
  -s 'config."membership.user.ldap.attribute"=["cn"]' \
  -s 'config.mode=["READ_ONLY"]' \
  -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' \
  -s 'config."drop.non.existing.groups.during.sync"=["false"]'

GROUP_MAPPER_ID="$($KCADM get "components?parent=platform&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" -r platform -q name=ldap-groups --fields id --format csv --noquotes)"
$KCADM create "user-storage/$LDAP_COMPONENT_ID/mappers/$GROUP_MAPPER_ID/sync?direction=fedToKeycloak" -r platform

echo "==> [5/6] OIDC clients for Argo CD and Grafana, with a groups claim mapper each"
ARGOCD_SECRET="$(kubectl -n "$KC_NS" get secret iam-secrets -o jsonpath='{.data.argocdClientSecret}' | base64 -d)"
GRAFANA_SECRET="$(kubectl -n "$KC_NS" get secret iam-secrets -o jsonpath='{.data.grafanaClientSecret}' | base64 -d)"

$KCADM create clients -r platform \
  -s clientId=argocd -s enabled=true -s protocol=openid-connect -s publicClient=false \
  -s clientAuthenticatorType=client-secret -s secret="$ARGOCD_SECRET" \
  -s 'redirectUris=["https://192.168.1.106:9080/auth/callback", "http://192.168.1.106:9080/auth/callback"]' \
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false

$KCADM create clients -r platform \
  -s clientId=grafana -s enabled=true -s protocol=openid-connect -s publicClient=false \
  -s clientAuthenticatorType=client-secret -s secret="$GRAFANA_SECRET" \
  -s 'redirectUris=["https://192.168.1.106:9082/login/generic_oauth", "http://192.168.1.106:9082/login/generic_oauth"]' \
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false

for CLIENT in argocd grafana; do
  CID="$($KCADM get clients -r platform -q clientId="$CLIENT" --fields id --format csv --noquotes)"
  $KCADM create "clients/$CID/protocol-mappers/models" -r platform \
    -s name=groups -s protocol=openid-connect -s protocolMapper=oidc-group-membership-mapper \
    -s 'config."full.path"="false"' \
    -s 'config."id.token.claim"="true"' \
    -s 'config."access.token.claim"="true"' \
    -s 'config."userinfo.token.claim"="true"' \
    -s 'config."claim.name"="groups"'
done

echo "==> [6/6] Verification"
echo "--- synced LDAP users ---"
$KCADM get users -r platform --fields username,email,enabled
echo "--- synced LDAP groups ---"
$KCADM get groups -r platform --fields name
echo "Done. Real end-to-end verification (a decoded access token showing the groups"
echo "claim) is documented in docs/evidence/samples/ -- this script sets the config up,"
echo "it doesn't re-run that check itself."
