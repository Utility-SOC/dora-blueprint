#!/usr/bin/env bash
# One-time setup: per-service admin/viewer LDAP groups for MinIO and GLPI, run once
# against the live directory — same "declarative infra, plus one script run once the
# service is actually up" pattern as configure-realm.sh/configure-glpi.sh.
#
# Deliberately does NOT touch Argo CD or Grafana's existing platform-admins/
# platform-viewers groups — those are already live, verified, and cited by evidence
# files (docs/evidence/samples/argocd-rbac-verification-*.txt); churning their group
# names for uniformity's sake would invalidate that evidence for no functional gain.
# New per-service groups are additive: MinIO and GLPI (the two newly-SSO'd services)
# get their own admin/viewer pairs so someone can hold, say, Grafana access without
# automatically holding MinIO access — real least-privilege separation, not just a
# renamed copy of the same two groups.
#
# Initial membership mirrors the existing platform-admins/platform-viewers split
# (alice+utility admin, bob viewer) for continuity — adjust before running if that's
# not what you want, or use onboard-user.sh afterward to add/remove people.
set -euo pipefail

LDAP_NS="${LDAP_NS:-openldap}"
BASE_DN="dc=platform,dc=local"

BIND_PW="$(kubectl -n "$LDAP_NS" get secret openldap-admin -o jsonpath='{.data.password}' | base64 -d)"
LDAPADD=(ldapadd -x -D "cn=admin,${BASE_DN}" -w "$BIND_PW")

create_group() {
  local NAME="$1"; shift
  local MEMBERS_LDIF=""
  for M in "$@"; do
    MEMBERS_LDIF+="member: cn=${M},ou=people,${BASE_DN}"$'\n'
  done
  echo "==> creating group ${NAME} (members: $*)"
  cat <<LDIF | kubectl -n "$LDAP_NS" exec -i deploy/openldap -- "${LDAPADD[@]}"
dn: cn=${NAME},ou=groups,${BASE_DN}
objectClass: groupOfNames
cn: ${NAME}
${MEMBERS_LDIF}
LDIF
}

echo "==> [1/4] minio-admins"
create_group minio-admins alice utility

echo "==> [2/4] minio-viewers"
create_group minio-viewers bob

echo "==> [3/4] glpi-admins"
create_group glpi-admins alice utility

echo "==> [4/4] glpi-users"
create_group glpi-users bob

echo
echo "Done. Trigger a Keycloak LDAP sync so these show up in the groups claim. CAUGHT LIVE:"
echo "this needs BOTH steps below, in order -- the group-mapper sync alone creates the new"
echo "Keycloak Group objects but does NOT reconcile existing users' (alice/bob/utility)"
echo "actual membership in them; only a full user re-sync does that."
echo
echo "  KC_POD=keycloak-keycloakx-0; KC_NS=keycloak"
echo "  LDAP_ID=\$(kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh get components -r platform -q name=openldap --fields id --format csv --noquotes)"
echo "  MAPPER_ID=\$(kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh get \"components?parent=\$LDAP_ID\" -r platform --fields id,name --format csv --noquotes | grep ldap-groups | cut -d, -f1)"
echo "  # 1. group-mapper sync (creates the new Group objects)"
echo "  kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh create \"user-storage/\$LDAP_ID/mappers/\$MAPPER_ID/sync?direction=fedToKeycloak\" -r platform"
echo "  # 2. full user sync (reconciles alice/bob/utility's actual membership -- REQUIRED)"
echo "  kubectl -n \$KC_NS exec \$KC_POD -- /opt/keycloak/bin/kcadm.sh create \"user-storage/\$LDAP_ID/sync?action=triggerFullSync\" -r platform""
echo
echo "Remember to mirror these groups into infrastructure/openldap/seed-ldif.yaml afterward —"
echo "this script changes only the live directory, same as onboard-user.sh."
