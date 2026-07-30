#!/usr/bin/env bash
# Makes the operator's own Keycloak/LDAP credentials deterministic and re-runnable,
# instead of the one-shot "generate a random password, show it once" pattern
# create-master-admin.sh and onboard-user.sh use for everyone else. Those scripts are
# right for onboarding a new person (nobody should be able to recover a password from
# this repo's own history); this script is for the operator's own daily-driver
# identities, where "I can't remember what I set it to" is the real failure mode, not
# leaking a shared secret to other users.
#
# Source of truth is infrastructure/keycloak/secrets/iam-secrets.enc.yaml (SOPS-
# encrypted, same file every other Keycloak/LDAP credential in this repo already lives
# in -- keycloak_admin_password already existed there; this adds
# keycloak_master_utility_password and utility_password alongside it, not a new,
# separate secret-handling path). Never touches a plaintext .env -- this repo has
# exactly one secret-at-rest mechanism, and duplicating it for one script's convenience
# would just be a second, weaker place secrets could leak from.
#
# Why this needs to exist at all: this Keycloak deployment runs on `dev-mem` (an
# in-memory H2 database, apps/keycloak.yaml) -- every realm, user, and credential
# lives only in the running pod's JVM heap. A pod restart doesn't just log everyone
# out, it erases the platform realm, LDAP federation, OIDC clients, and every
# non-bootstrap user entirely. Re-provisioning the realm itself is
# configure-realm.sh's job (run that first if a restart actually happened and
# `platform` realm 404s) -- this script only re-establishes the operator's own
# credentials once the realm exists, idempotently, so re-running it after a restart
# (or at any other time) converges on the same known passwords rather than minting new
# random ones each time.
#
# Usage: persist-operator-credentials.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KC_POD="${KC_POD:-keycloak-keycloakx-0}"
KC_NS="${KC_NS:-keycloak}"
LDAP_NS="${LDAP_NS:-openldap}"
BASE_DN="dc=platform,dc=local"
KCADM="kubectl -n $KC_NS exec $KC_POD -- /opt/keycloak/bin/kcadm.sh"

echo "==> [1/6] Decrypt the operator-credential fields"
SECRETS_TMP="$(mktemp)"
trap 'shred -u "$SECRETS_TMP" 2>/dev/null || rm -f "$SECRETS_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/keycloak/secrets/iam-secrets.enc.yaml" > "$SECRETS_TMP"
NEW_ADMIN_PW="$(awk '/^keycloak_admin_password:/ {print $2}' "$SECRETS_TMP")"
MASTER_UTILITY_PW="$(awk '/^keycloak_master_utility_password:/ {print $2}' "$SECRETS_TMP")"
PLATFORM_UTILITY_PW="$(awk '/^utility_password:/ {print $2}' "$SECRETS_TMP")"
LDAP_BIND_PW="$(awk '/^ldap_bind_password:/ {print $2}' "$SECRETS_TMP")"

echo "==> [2/6] Log in to the master realm -- try the target admin password first, fall back to whatever the live k8s Secret currently holds"
OLD_ADMIN_PW="$(kubectl -n "$KC_NS" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
if ! $KCADM config credentials --server http://localhost:8080/auth --realm master --user admin --password "$NEW_ADMIN_PW" 2>/dev/null; then
  $KCADM config credentials --server http://localhost:8080/auth --realm master --user admin --password "$OLD_ADMIN_PW"
fi

echo "==> [3/6] Reconcile the bootstrap admin's own password to the target value"
BOOTSTRAP_ID="$($KCADM get users -r master -q username=admin --fields id --format csv --noquotes | tail -1)"
$KCADM set-password -r master --userid "$BOOTSTRAP_ID" --new-password "$NEW_ADMIN_PW" --temporary=false

echo "==> [4/6] Update the live k8s Secret so a future pod restart bootstraps with the same password"
kubectl -n "$KC_NS" create secret generic keycloak-admin \
  --from-literal=password="$NEW_ADMIN_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> [5/6] Ensure the master-realm 'utility' super-admin exists with the target password"
if ! $KCADM get users -r master -q username=utility --fields id --format csv --noquotes | grep -q .; then
  echo "    (didn't exist -- creating, matching create-master-admin.sh's own shape)"
  $KCADM create users -r master -s username=utility -s enabled=true -s emailVerified=true
fi
UTILITY_ID="$($KCADM get users -r master -q username=utility --fields id --format csv --noquotes | tail -1)"
$KCADM set-password -r master --userid "$UTILITY_ID" --new-password "$MASTER_UTILITY_PW" --temporary=false
$KCADM add-roles -r master --uusername utility --rolename admin 2>/dev/null || true # already granted -- tolerate, same as configure-service-groups.sh's policy-attach

echo "==> [6/6] Reconcile the platform-realm (LDAP-backed) 'utility' user's own password"
kubectl -n "$LDAP_NS" exec deploy/openldap -- ldappasswd -x \
  -D "cn=admin,${BASE_DN}" -w "$LDAP_BIND_PW" -s "$PLATFORM_UTILITY_PW" \
  "cn=utility,ou=people,${BASE_DN}"

echo
echo "Done. Both 'utility' identities (master-realm admin, platform-realm LDAP) and the"
echo "bootstrap admin now match infrastructure/keycloak/secrets/iam-secrets.enc.yaml --"
echo "re-run this any time (after a restart, after rotating the secret file, or just to"
echo "confirm) to converge back onto those same values, never a freshly random one."
