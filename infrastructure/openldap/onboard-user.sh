#!/usr/bin/env bash
# Generic, reusable user onboarding — run this any time a real new person needs an
# identity on the platform, not just during initial bootstrap. Creates (or reuses, if
# already present) an OpenLDAP user entry and adds them to one or more existing groups.
# This is the one script in infrastructure/openldap/ meant to be run repeatedly over the
# life of the lab, unlike configure-service-groups.sh's one-time setup role.
#
# Deliberately does NOT create groups that don't already exist — group membership drives
# real access (Keycloak group federation -> OIDC groups claim -> each service's own
# admin/viewer mapping), so a typo'd group name should fail loudly, not silently create
# a new, unwired group that looks like it granted access but didn't.
#
# Password handling matches configure-glpi.sh's "generate, print once, never persist"
# discipline — this script does not write the plaintext anywhere, including its own
# stdout log if redirected; treat the terminal output as the only copy.
#
# Usage: onboard-user.sh <uid> <sn> <email> <group1>[,<group2>,...]
# Example: onboard-user.sh carol "Carol Analyst" carol@platform.local platform-viewers,minio-viewers
set -euo pipefail

UID_NAME="${1:?usage: onboard-user.sh <uid> <sn> <email> <group1>[,<group2>,...]}"
SN="${2:?usage: onboard-user.sh <uid> <sn> <email> <group1>[,<group2>,...]}"
EMAIL="${3:?usage: onboard-user.sh <uid> <sn> <email> <group1>[,<group2>,...]}"
GROUPS_CSV="${4:?usage: onboard-user.sh <uid> <sn> <email> <group1>[,<group2>,...]}"

LDAP_NS="${LDAP_NS:-openldap}"
BASE_DN="dc=platform,dc=local"
USER_DN="cn=${UID_NAME},ou=people,${BASE_DN}"

BIND_PW="$(kubectl -n "$LDAP_NS" get secret openldap-admin -o jsonpath='{.data.password}' | base64 -d)"
LDAPBIND=(ldapsearch -x -D "cn=admin,${BASE_DN}" -w "$BIND_PW")
LDAPMOD=(ldapmodify -x -D "cn=admin,${BASE_DN}" -w "$BIND_PW")
LDAPADD=(ldapadd -x -D "cn=admin,${BASE_DN}" -w "$BIND_PW")

echo "==> [1/3] Check whether $UID_NAME already exists"
if kubectl -n "$LDAP_NS" exec deploy/openldap -- "${LDAPBIND[@]}" -b "$USER_DN" -s base >/dev/null 2>&1; then
  echo "    $UID_NAME already exists — skipping creation, only wiring group membership below"
else
  echo "==> [2/3] Create $UID_NAME (a real random password, shown once below — save it now)"
  NEW_PW="$(openssl rand -base64 18 | tr -d '/+=' | head -c 18)"
  # {SSHA} via slappasswd, bundled in the openldap image — same hashing scheme every
  # other user in seed-ldif.yaml already uses, one-way, safe to end up in this script's
  # own log (the hash, never the plaintext, which is only echoed to the operator's
  # terminal below and nowhere else).
  SSHA_HASH="$(kubectl -n "$LDAP_NS" exec deploy/openldap -- slappasswd -s "$NEW_PW")"
  cat <<LDIF | kubectl -n "$LDAP_NS" exec -i deploy/openldap -- "${LDAPADD[@]}"
dn: ${USER_DN}
objectClass: inetOrgPerson
cn: ${UID_NAME}
sn: ${SN}
uid: ${UID_NAME}
mail: ${EMAIL}
userPassword: ${SSHA_HASH}
LDIF
  echo
  echo "    New user '$UID_NAME' password (save this, shown once): $NEW_PW"
  echo
fi

echo "==> [3/3] Add $UID_NAME to group(s): $GROUPS_CSV"
IFS=',' read -ra GROUP_LIST <<< "$GROUPS_CSV"
for GROUP in "${GROUP_LIST[@]}"; do
  GROUP_DN="cn=${GROUP},ou=groups,${BASE_DN}"
  if ! kubectl -n "$LDAP_NS" exec deploy/openldap -- "${LDAPBIND[@]}" -b "$GROUP_DN" -s base >/dev/null 2>&1; then
    echo "    ERROR: group '$GROUP' does not exist ($GROUP_DN) — not creating it implicitly." >&2
    echo "    Create it first (see configure-service-groups.sh for the pattern) or fix the typo." >&2
    exit 1
  fi
  cat <<LDIF | kubectl -n "$LDAP_NS" exec -i deploy/openldap -- "${LDAPMOD[@]}"
dn: ${GROUP_DN}
changetype: modify
add: member
member: ${USER_DN}
LDIF
  echo "    added to $GROUP"
done

echo
echo "Done. Remember to mirror this user/membership into infrastructure/openldap/seed-ldif.yaml"
echo "afterward (git-committed, not auto-synced from live LDAP state) if it should survive a"
echo "fresh PVC — same discipline seed-ldif.yaml's own header comment already documents for"
echo "the 'utility' user."
echo
echo "It can take up to Keycloak's LDAP sync interval for this user/membership to appear in"
echo "Keycloak — trigger an immediate sync if needed. CAUGHT LIVE: this needs BOTH of the"
echo "following, in order, not just the first one -- the group-mapper sync alone creates/"
echo "updates the Keycloak Group objects, but does NOT reconcile an already-synced existing"
echo "user's actual membership in them; only a full user re-sync does that."
echo
echo "  KC_POD=keycloak-keycloakx-0; KC_NS=keycloak"
echo "  LDAP_ID=\$(kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh get components -r platform -q name=openldap --fields id --format csv --noquotes)"
echo "  MAPPER_ID=\$(kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh get \"components?parent=\$LDAP_ID\" -r platform --fields id,name --format csv --noquotes | grep ldap-groups | cut -d, -f1)"
echo "  # 1. group-mapper sync (creates/updates Group objects for any brand-new group)"
echo "  kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh create \"user-storage/\$LDAP_ID/mappers/\$MAPPER_ID/sync?direction=fedToKeycloak\" -r platform"
echo "  # 2. full user sync (reconciles every existing user's actual membership -- REQUIRED,"
echo "  #    not just belt-and-suspenders; step 1 alone leaves existing users' membership stale)"
echo "  kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh create \"user-storage/\$LDAP_ID/sync?action=triggerFullSync\" -r platform"
