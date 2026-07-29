#!/usr/bin/env bash
# Phase 11 (Incident response): one-time GLPI setup, run against a live instance -- mirrors
# infrastructure/keycloak/configure-realm.sh's and
# infrastructure/observability/configure-grafana-alerting.sh's established "declarative infra,
# plus one script run once the service is actually up" pattern, since REST-enablement, the
# default admin password, and a service-account API token can't be file-provisioned the way a
# Deployment spec can.
#
# CAUGHT LIVE, in order:
# 1. `bin/console list` (and therefore every other console command) crashes outright with
#    "DirectoryIterator::__construct(/var/glpi/marketplace): Failed to open directory" -- GLPI
#    10.x's own docs note the marketplace path "requires manual volume configuration" but the
#    image's own startup script doesn't create it even without one configured. Created here,
#    not added as a Deployment volume, since it's only needed for this one-time CLI setup, not
#    GLPI's normal web-serving path (which worked fine without it).
# 2. The REST API is disabled by default (`enable_api`), and even once enabled, login via
#    username/password on `initSession` is *separately* disabled by default
#    (`enable_api_login_credentials`, "usage of initSession resource with credentials is
#    disabled") -- both confirmed by real 403-shaped API error bodies, not assumed from docs.
# 3. GLPI's own REST API never returns a freshly generated `api_token` value in the update
#    response (`_reset_api_token`) -- confirmed by reading src/User.php directly: the value is
#    written to the users table but never echoed back, apparently by design (matching Grafana's
#    own "shown once" service-account-token philosophy, just via a different mechanism -- GLPI
#    doesn't even show it once via the API). The only way to retrieve it is a direct DB read,
#    same class of thing this whole repo already does for bootstrap credentials.
#
# Idempotent-ish, same discipline as configure-realm.sh: re-running this creates a SECOND
# drill-automation user rather than reusing the first -- delete the existing one via GLPI's own
# UI/API first to regenerate cleanly.
set -euo pipefail

GLPI_URL="${GLPI_URL:-http://192.168.1.106:9085}"
GLPI_NS="${GLPI_NS:-glpi}"

echo "==> [1/6] Ensure /var/glpi/marketplace exists (missing by default, crashes bin/console)"
kubectl -n "$GLPI_NS" exec deploy/glpi -- mkdir -p /var/glpi/marketplace
kubectl -n "$GLPI_NS" exec deploy/glpi -- chown www-data:www-data /var/glpi/marketplace

CONSOLE="kubectl -n $GLPI_NS exec deploy/glpi -- su www-data -s /bin/bash -c"

echo "==> [2/6] Enable the REST API and credential-based login"
$CONSOLE "cd /var/www/glpi && php bin/console config:set enable_api 1"
$CONSOLE "cd /var/www/glpi && php bin/console config:set enable_api_login_credentials 1"

echo "==> [3/6] Authenticate as the default super-admin (glpi/glpi, still default at this point)"
ADMIN_SESSION_TMP="$(mktemp)"
curl -s -X GET "$GLPI_URL/apirest.php/initSession" \
  -H 'Authorization: Basic Z2xwaTpnbHBp' > "$ADMIN_SESSION_TMP"
ADMIN_SESSION="$(python3 -c "import json; print(json.load(open('$ADMIN_SESSION_TMP'))['session_token'])")"
rm -f "$ADMIN_SESSION_TMP"

echo "==> [4/6] Rotate the default admin password"
GLPI_ADMIN_PW_TMP="$(mktemp)"
trap 'shred -u "$GLPI_ADMIN_PW_TMP" 2>/dev/null || rm -f "$GLPI_ADMIN_PW_TMP"' EXIT
NEW_ADMIN_PW="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
cat > "$GLPI_ADMIN_PW_TMP" <<EOF
{"input":{"id":2,"password":"$NEW_ADMIN_PW","password2":"$NEW_ADMIN_PW"}}
EOF
curl -s -X PUT "$GLPI_URL/apirest.php/User/2" \
  -H "Session-Token: $ADMIN_SESSION" -H 'Content-Type: application/json' \
  -d @"$GLPI_ADMIN_PW_TMP" > /dev/null
rm -f "$GLPI_ADMIN_PW_TMP"
echo "New admin (id 2, 'glpi') password -- save this, shown once: $NEW_ADMIN_PW"

echo "==> [5/6] Create the drill-automation service account (Technician profile, id 6 -- can create/manage tickets, not a superadmin)"
DRILL_USER_TMP="$(mktemp)"
NEW_DRILL_PW="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
cat > "$DRILL_USER_TMP" <<EOF
{"input":{"name":"drill-automation","password":"$NEW_DRILL_PW","password2":"$NEW_DRILL_PW","_profiles_id":6,"_entities_id":0,"is_active":1}}
EOF
CREATE_RESULT="$(curl -s -X POST "$GLPI_URL/apirest.php/User/" \
  -H "Session-Token: $ADMIN_SESSION" -H 'Content-Type: application/json' \
  -d @"$DRILL_USER_TMP")"
rm -f "$DRILL_USER_TMP"
DRILL_USER_ID="$(echo "$CREATE_RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
echo "drill-automation user id: $DRILL_USER_ID"

RESET_TOKEN_TMP="$(mktemp)"
cat > "$RESET_TOKEN_TMP" <<EOF
{"input":{"id":$DRILL_USER_ID,"_reset_api_token":true}}
EOF
curl -s -X PUT "$GLPI_URL/apirest.php/User/$DRILL_USER_ID" \
  -H "Session-Token: $ADMIN_SESSION" -H 'Content-Type: application/json' \
  -d @"$RESET_TOKEN_TMP" > /dev/null
rm -f "$RESET_TOKEN_TMP"

echo "==> [6/6] Read the generated token directly from the database (never returned by the API)"
DRILL_API_TOKEN="$(kubectl -n "$GLPI_NS" exec deploy/mariadb -- mariadb -u root -N -s \
  -p"$(kubectl -n "$GLPI_NS" get secret glpi-db -o jsonpath='{.data.mariadbRootPassword}' | base64 -d)" \
  glpi -e "SELECT api_token FROM glpi_users WHERE id=$DRILL_USER_ID;")"

echo
echo "drill-automation API token (SOPS-encrypt this now into"
echo "infrastructure/glpi/secrets/glpi-api-token.enc.yaml, key glpi_api_token -- GLPI never shows"
echo "this again):"
echo "$DRILL_API_TOKEN"
