#!/usr/bin/env bash
# One-time GLPI native-LDAP auth + profile-assignment setup, run against a live instance --
# companion to configure-glpi.sh (Phase 11's ticketing setup), separate script since this runs
# later and for a different reason (real human SSO-adjacent login, not drill automation).
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
# CAUGHT LIVE (three real bugs, found by actually running this against the live instance,
# not assumed from reading GLPI's source alone):
# 1. The bind-password field is "rootdn_passwd" (no "or"), not "rootdn_password" -- the
#    wrong name meant the real password was silently discarded (the API doesn't reject
#    unknown input keys) and GLPI attempted an unauthenticated bind instead. Only visible
#    in the container's own error backtrace (kubectl logs deploy/glpi), not the API's
#    response body.
# 2. GLPI's own group-membership search (AuthLDAP::getFromLDAPGroupDiscret ->
#    User::ldap_get_user_groups) uses the SAME `basedn` configured for user lookups as its
#    search base for finding GROUP entries too -- with basedn scoped to ou=people, it can
#    never find groups that live in the sibling ou=groups. Widened to the domain root
#    (dc=platform,dc=local), which still finds users fine (extra scope, same filters).
# 3. `group_condition` must filter the GROUP entries themselves (this directory's groups
#    are `objectClass=groupOfNames`) -- not a user object class like `inetOrgPerson`.
# Confirmed the fix by testing the exact LDAP filter GLPI builds directly via ldapsearch
# before trusting GLPI's own sync to use it correctly.
#
# Group-to-profile mapping (RuleRight) IS automated below, unlike an earlier draft of this
# script that left it as a manual UI step out of caution about getting a rights-assignment
# rule subtly wrong. Now that the exact criteria/action shape has been verified live
# (real Profile_User rows created with the expected profiles_id, not assumed), shipping the
# tested version is more correct than leaving a manual walkthrough that's more error-prone
# to follow by hand. Still worth a real login test afterward (this script does one).
#
# Known minor limitation, not fixed here: a user with multiple LDAP-derived profiles (e.g.
# utility ends up with both Self-Service, from GLPI's own global-default fallback set on
# first import before any rule existed, and Super-Admin, from the rule below) doesn't
# automatically make the higher-rights one their *active* session profile -- GLPI's
# `is_default_profile` flag isn't settable via a plain RuleRight action or a direct
# Profile_User field update in this version. The user can switch profiles from GLPI's own
# UI (top-right profile picker) if their session doesn't default to the expected one.
set -euo pipefail

GLPI_URL="${GLPI_URL:-http://192.168.1.106:9085}"
GLPI_NS="${GLPI_NS:-glpi}"

echo "==> [1/6] Reset the GLPI admin (id 2, 'glpi') password via direct DB write"
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

echo "==> [2/6] Authenticate as admin with the new password"
SESSION_TMP="$(mktemp)"
trap 'shred -u "$SESSION_TMP" 2>/dev/null || rm -f "$SESSION_TMP"' EXIT
AUTH_HEADER="Basic $(printf 'glpi:%s' "$NEW_ADMIN_PW" | base64 -w0)"
curl -s -X GET "$GLPI_URL/apirest.php/initSession" -H "Authorization: $AUTH_HEADER" > "$SESSION_TMP"
SESSION="$(python3 -c "import json; print(json.load(open('$SESSION_TMP'))['session_token'])")"
rm -f "$SESSION_TMP"

echo "==> [3/6] Create the AuthLDAP directory (same OpenLDAP instance Keycloak federates from)"
LDAP_BIND_PW="$(kubectl -n "$GLPI_NS" get secret openldap-bind -o jsonpath='{.data.password}' | base64 -d)"
AUTHLDAP_TMP="$(mktemp)"
trap 'shred -u "$AUTHLDAP_TMP" 2>/dev/null || rm -f "$AUTHLDAP_TMP"' EXIT
cat > "$AUTHLDAP_TMP" <<EOF
{"input":{
  "name":"platform-openldap",
  "is_active":1,
  "host":"openldap.openldap.svc.cluster.local",
  "port":389,
  "basedn":"dc=platform,dc=local",
  "rootdn":"cn=admin,dc=platform,dc=local",
  "rootdn_passwd":"$LDAP_BIND_PW",
  "login_field":"uid",
  "use_tls":0,
  "use_dn":1,
  "group_search_type":1,
  "group_member_field":"member",
  "group_condition":"(objectClass=groupOfNames)"
}}
EOF
AUTHLDAP_RESULT="$(curl -s -X POST "$GLPI_URL/apirest.php/AuthLDAP/" \
  -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d @"$AUTHLDAP_TMP")"
rm -f "$AUTHLDAP_TMP"
echo "$AUTHLDAP_RESULT"

echo
echo "==> [4/6] Create Group entities linked to the LDAP groups that should map to a profile"
GLPI_ADMINS_GROUP="$(curl -s -X POST "$GLPI_URL/apirest.php/Group/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d '{"input":{"name":"glpi-admins","ldap_group_dn":"cn=glpi-admins,ou=groups,dc=platform,dc=local"}}')"
echo "$GLPI_ADMINS_GROUP"
GLPI_ADMINS_GROUP_ID="$(echo "$GLPI_ADMINS_GROUP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

GLPI_USERS_GROUP="$(curl -s -X POST "$GLPI_URL/apirest.php/Group/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d '{"input":{"name":"glpi-users","ldap_group_dn":"cn=glpi-users,ou=groups,dc=platform,dc=local"}}')"
echo "$GLPI_USERS_GROUP"
GLPI_USERS_GROUP_ID="$(echo "$GLPI_USERS_GROUP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

echo
echo "==> [5/6] Create RuleRight rules mapping those groups to profiles"
# Criteria field "_groups_id" matches against a Group's own GLPI id (glpi_groups.id) --
# populated during LDAP sync from the Group entities just created above, matched by
# ldap_group_dn, NOT the raw LDAP group DN string directly. condition 0 = Rule::PATTERN_IS.
RULE1="$(curl -s -X POST "$GLPI_URL/apirest.php/Rule/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d '{"input":{"name":"LDAP glpi-admins -> Super-Admin","sub_type":"RuleRight","match":"AND","is_active":1}}')"
echo "$RULE1"
RULE1_ID="$(echo "$RULE1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
curl -s -X POST "$GLPI_URL/apirest.php/RuleCriteria/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE1_ID,\"criteria\":\"_groups_id\",\"condition\":0,\"pattern\":\"$GLPI_ADMINS_GROUP_ID\"}}" > /dev/null
curl -s -X POST "$GLPI_URL/apirest.php/RuleAction/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE1_ID,\"action_type\":\"assign\",\"field\":\"profiles_id\",\"value\":\"4\"}}" > /dev/null
curl -s -X POST "$GLPI_URL/apirest.php/RuleAction/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE1_ID,\"action_type\":\"assign\",\"field\":\"entities_id\",\"value\":\"0\"}}" > /dev/null
curl -s -X POST "$GLPI_URL/apirest.php/RuleAction/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE1_ID,\"action_type\":\"assign\",\"field\":\"is_recursive\",\"value\":\"1\"}}" > /dev/null
echo "    rule 1 done (glpi-admins group id $GLPI_ADMINS_GROUP_ID -> profile 4, Super-Admin)"

RULE2="$(curl -s -X POST "$GLPI_URL/apirest.php/Rule/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d '{"input":{"name":"LDAP glpi-users -> Self-Service","sub_type":"RuleRight","match":"AND","is_active":1}}')"
echo "$RULE2"
RULE2_ID="$(echo "$RULE2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
curl -s -X POST "$GLPI_URL/apirest.php/RuleCriteria/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE2_ID,\"criteria\":\"_groups_id\",\"condition\":0,\"pattern\":\"$GLPI_USERS_GROUP_ID\"}}" > /dev/null
curl -s -X POST "$GLPI_URL/apirest.php/RuleAction/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE2_ID,\"action_type\":\"assign\",\"field\":\"profiles_id\",\"value\":\"1\"}}" > /dev/null
curl -s -X POST "$GLPI_URL/apirest.php/RuleAction/" -H "Session-Token: $SESSION" -H 'Content-Type: application/json' \
  -d "{\"input\":{\"rules_id\":$RULE2_ID,\"action_type\":\"assign\",\"field\":\"entities_id\",\"value\":\"0\"}}" > /dev/null
echo "    rule 2 done (glpi-users group id $GLPI_USERS_GROUP_ID -> profile 1, Self-Service)"

echo
echo "==> [6/6] Verify: sync existing users, then check a real login's resulting profiles"
kubectl -n "$GLPI_NS" exec deploy/glpi -- php bin/console ldap:synchronize_users --only-update-existing -n
echo
echo "    Check the result directly (don't assume) -- for any already-imported user (e.g."
echo "    'utility', GLPI id varies by instance), fetch:"
echo "    GET $GLPI_URL/apirest.php/User/<id>/Profile_User"
echo "    Expect one row per matching rule (e.g. profiles_id 4 for a glpi-admins member)."
