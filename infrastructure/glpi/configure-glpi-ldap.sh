#!/usr/bin/env bash
# One-time GLPI native-LDAP auth setup, run against a live instance -- companion to
# configure-glpi.sh (Phase 11's ticketing setup), separate script since this runs later
# and for a different reason (real human SSO-adjacent login, not drill automation).
#
# GLPI has no OIDC/SAML support in core, and its own marketplace search requires a "GLPI
# Network" registration key this lab doesn't have, so a third-party OIDC plugin can't be
# vetted from here the way every other tool choice in this repo has been (real, verified
# trust-tier research) -- see docs/04-limitations.md. Native LDAP auth is a real, built-in,
# well-documented GLPI feature instead: not true single-sign-on (still GLPI's own login
# page, still a separate session), but the same username/password as everywhere else on
# the platform, against the same OpenLDAP directory Keycloak already federates from.
#
# Binds as cn=admin (the one LDAP admin DN this lab has, same one Keycloak's own
# federation uses) rather than a dedicated read-only bind account -- a real deployment
# should scope this down; stated plainly, not silently done, per this repo's own
# discipline.
#
# Step [1] resets the admin (id=2) password via a direct database write, not the API --
# there is no working admin session to authenticate the API call that would normally do
# this (GLPI never re-shows a rotated password, see configure-glpi.sh's own note), so this
# bypasses the app layer entirely, the same technique already used there to read back the
# drill-automation token GLPI's API itself never returns.
#
# CAUGHT LIVE: the first version of this script sent the bind password as
# "rootdn_password" in the AuthLDAP payload -- GLPI's actual internal field is
# "rootdn_passwd" (no "or"), confirmed by reading src/AuthLDAP.php's own
# tryToConnectToServer(), which reads $ldap_method['rootdn_passwd']. The wrong field
# name meant the real password was silently discarded (the API doesn't reject unknown
# input keys) and GLPI attempted an unauthenticated bind instead, failing with a generic
# "Unable to connect to the LDAP directory" that gave no hint the field name was wrong --
# only visible in the container's own error backtrace (kubectl logs deploy/glpi), not the
# API's response body. Confirmed the fix live: a real LDAP bind via raw PHP (same
# credentials) succeeded throughout, isolating the bug to this one field name.
#
# Step [4] (profile-assignment rules) is deliberately NOT automated. GLPI's rules engine
# (RuleRight: criteria + actions, used to map an LDAP group to a GLPI profile) has
# internal field/action codes that are easy to get subtly wrong without live iteration
# against the actual instance -- and getting an access-rights rule wrong the wrong
# direction is a real security mistake, not just a cosmetic one. Printed as clear manual
# UI steps instead of a guessed API payload, matching this repo's own "say so, don't fake
# confidence" discipline (docs/04-limitations.md, the GitHub-vs-GLPI ticketing decision,
# Bitnami-vs-official image choices) rather than shipping something unverified.
set -euo pipefail

GLPI_URL="${GLPI_URL:-http://192.168.1.106:9085}"
GLPI_NS="${GLPI_NS:-glpi}"

echo "==> [1/4] Reset the GLPI admin (id 2, 'glpi') password via direct DB write"
CREDS_TMP="$(mktemp)"
trap 'shred -u "$CREDS_TMP" 2>/dev/null || rm -f "$CREDS_TMP"' EXIT
kubectl -n "$GLPI_NS" exec deploy/glpi -- php -r \
  '$p=bin2hex(random_bytes(12)); echo $p.PHP_EOL.password_hash($p, PASSWORD_BCRYPT).PHP_EOL;' > "$CREDS_TMP"
NEW_ADMIN_PW="$(sed -n '1p' "$CREDS_TMP")"
NEW_ADMIN_HASH="$(sed -n '2p' "$CREDS_TMP")"

MARIADB_ROOT_PW="$(kubectl -n "$GLPI_NS" get secret glpi-db -o jsonpath='{.data.mariadbRootPassword}' | base64 -d)"
kubectl -n "$GLPI_NS" exec deploy/mariadb -- env DBROOT="$MARIADB_ROOT_PW" NEWHASH="$NEW_ADMIN_HASH" sh -c \
  'mariadb -u root -p"$DBROOT" glpi -e "UPDATE glpi_users SET \`password\`=\"$NEWHASH\" WHERE id=2"'
rm -f "$CREDS_TMP"
echo "    New admin (id 2, 'glpi') password -- save this, shown once: $NEW_ADMIN_PW"

echo "==> [2/4] Authenticate as admin with the new password"
SESSION_TMP="$(mktemp)"
trap 'shred -u "$SESSION_TMP" 2>/dev/null || rm -f "$SESSION_TMP"' EXIT
AUTH_HEADER="Basic $(printf 'glpi:%s' "$NEW_ADMIN_PW" | base64 -w0)"
curl -s -X GET "$GLPI_URL/apirest.php/initSession" -H "Authorization: $AUTH_HEADER" > "$SESSION_TMP"
SESSION="$(python3 -c "import json; print(json.load(open('$SESSION_TMP'))['session_token'])")"
rm -f "$SESSION_TMP"

echo "==> [3/4] Create the AuthLDAP directory (same OpenLDAP instance Keycloak federates from)"
LDAP_BIND_PW="$(kubectl -n "$GLPI_NS" get secret openldap-bind -o jsonpath='{.data.password}' | base64 -d)"
AUTHLDAP_TMP="$(mktemp)"
trap 'shred -u "$AUTHLDAP_TMP" 2>/dev/null || rm -f "$AUTHLDAP_TMP"' EXIT
cat > "$AUTHLDAP_TMP" <<EOF
{"input":{
  "name":"platform-openldap",
  "is_active":1,
  "host":"openldap.openldap.svc.cluster.local",
  "port":389,
  "basedn":"ou=people,dc=platform,dc=local",
  "rootdn":"cn=admin,dc=platform,dc=local",
  "rootdn_passwd":"$LDAP_BIND_PW",
  "login_field":"uid",
  "use_tls":0
}}
EOF
curl -s -X POST "$GLPI_URL/apirest.php/AuthLDAP/" \
  -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d @"$AUTHLDAP_TMP"
rm -f "$AUTHLDAP_TMP"
echo
echo "    directory created -- verify in the UI (Setup > Authentication > LDAP directories)"
echo "    with a real test login before trusting it (Setup > Authentication > LDAP > Test)"

echo
echo "==> [4/4] MANUAL STEP -- profile-assignment rules (not automated, see this script's header)"
echo "    In GLPI's own UI: Administration > Rules > Rules for assigning rights > Add a new rule"
echo "    Rule 1: criteria 'LDAP directory group' contains 'glpi-admins' -> action 'Profile'"
echo "            assign 'Super-Admin', 'Entity' assign root entity, recursive"
echo "    Rule 2: criteria 'LDAP directory group' contains 'glpi-users' -> action 'Profile'"
echo "            assign 'Self-Service' (or 'Observer', whichever this instance's default"
echo "            profile set calls the read-mostly one), same entity assignment"
echo "    Test both by logging in as 'bob' and 'utility' via GLPI's LDAP-auth login form"
echo "    afterward and confirming the resulting profile matches -- checked directly against"
echo "    a real login, not assumed from the rule's own saved state."
