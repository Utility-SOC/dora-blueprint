#!/usr/bin/env bash
# Creates a persistent, named master-realm Keycloak admin -- a real replacement for
# relying on the bootstrap "admin" account long-term, not a second copy of it. The
# bootstrap admin (Keycloak's own auto-created superuser, password in the
# `keycloak-admin` K8s Secret) is meant to be a break-glass identity, not a daily
# driver; this gives you a properly named one instead.
#
# Deliberately a MASTER-realm local user, not a platform-realm LDAP one -- the master
# realm has its own separate user database (no LDAP federation configured for it, and
# shouldn't be, since it administers Keycloak itself). This is a genuinely different
# kind of admin than `utility` (application admin, via infrastructure/openldap/ + the
# platform realm) -- see the conversation this script came out of for why those two
# were kept deliberately separate rather than merged into one identity.
#
# Grants the "admin" REALM role in master (not a client role) -- CAUGHT LIVE: the first
# version of this script tried `--cclientid realm-management`, which doesn't exist in
# master (that client name only exists from within a realm referring to itself;
# master's own self-admin client from master's perspective is called "master-realm",
# and even that client has no composite "realm-admin" role, only granular ones like
# manage-realm/manage-users). Checked what the actual bootstrap admin account has
# instead of guessing further: a single realm-level role literally named "admin",
# which is the real composite Keycloak uses for full master-realm admin. This grants
# exactly that, confirmed to match the bootstrap admin's own role-mappings exactly.
#
# Usage: create-master-admin.sh <username>
# Example: create-master-admin.sh keycloak-operator
set -euo pipefail

NEW_ADMIN="${1:?usage: create-master-admin.sh <username>}"

KC_POD="${KC_POD:-keycloak-keycloakx-0}"
KC_NS="${KC_NS:-keycloak}"
KCADM="kubectl -n $KC_NS exec $KC_POD -- /opt/keycloak/bin/kcadm.sh"

echo "==> [1/4] Login as the bootstrap admin"
KC_ADMIN_PW="$(kubectl -n "$KC_NS" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
$KCADM config credentials --server http://localhost:8080/auth --realm master --user admin --password "$KC_ADMIN_PW"

echo "==> [2/4] Create $NEW_ADMIN in the master realm (a real random password, shown once below)"
NEW_PW="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
$KCADM create users -r master \
  -s username="$NEW_ADMIN" -s enabled=true -s emailVerified=true
$KCADM set-password -r master --username "$NEW_ADMIN" --new-password "$NEW_PW"

echo "==> [3/4] Grant the 'admin' realm role (same one the bootstrap admin has)"
$KCADM add-roles -r master --uusername "$NEW_ADMIN" --rolename admin

echo "==> [4/4] Done"
echo
echo "New Keycloak master-realm admin (save this, shown once):"
echo "  URL:      http://192.168.1.106:9083/auth/admin/"
echo "  Username: $NEW_ADMIN"
echo "  Password: $NEW_PW"
echo
echo "Verify by logging in with these at the URL above before relying on it -- checked"
echo "directly, not assumed from the role-grant call succeeding."
echo
echo "The bootstrap 'admin' account and its secret (kubectl -n keycloak get secret"
echo "keycloak-admin) still exist and still work -- this doesn't rotate or disable it,"
echo "only adds a second, properly named admin. Disable/rotate the bootstrap one"
echo "separately once you've confirmed $NEW_ADMIN works, if you want to stop relying on it."
