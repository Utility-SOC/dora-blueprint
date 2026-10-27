#!/usr/bin/env bash
# MFA enforcement for the platform realm, switchable rather than hard-wired. Run after
# configure-realm.sh. Kept separate from it (same reasoning as configure-minio-oidc.sh): MFA
# policy is something an operator changes later, configure-realm.sh is a one-time build.
#
#   MFA_MODE=optional  stock Keycloak browser flow -- OTP is asked for only from users who
#                      enrolled one themselves. This is Keycloak's default, i.e. "MFA off".
#   MFA_MODE=groups    OTP required for members of $MFA_GROUPS (default: platform-admins),
#                      who are forced to enrol on next login. Everyone else as `optional`.
#   MFA_MODE=all       OTP required for every user in the realm (default).
#
# Mechanism: a `browser-mfa` flow, rebuilt from a fresh copy of the stock `browser` flow on
# every run and bound as the realm's browser flow -- so re-running is idempotent and a mode
# change never inherits leftovers from the previous mode. `groups` uses Keycloak's built-in
# "Condition - User Role" against a realm role (`mfa-required`) that this script maps onto
# the chosen LDAP-federated groups; role membership is owned by this script, not by hand.
#
# Only the browser flow is touched. That is the only flow any platform client uses:
# configure-realm.sh/configure-minio-oidc.sh create every client with
# directAccessGrantsEnabled=false, so there is no password-grant path around this. The
# `master` realm (break-glass admin, create-master-admin.sh) is deliberately left alone.
#
# Not network-aware: Keycloak has no built-in "client IP / network" condition, and today
# every request reaches it through `kubectl port-forward`, so the source address it sees is
# the port-forward itself, not the user's network. See docs/04-limitations.md.
set -euo pipefail

MFA_MODE="${MFA_MODE:-all}"
MFA_GROUPS="${MFA_GROUPS:-platform-admins}"
REALM="${REALM:-platform}"
FLOW=browser-mfa
ROLE=mfa-required
case "$MFA_MODE" in
  optional|groups|all) ;;
  *) echo "unknown MFA_MODE '$MFA_MODE' -- expected optional, groups, or all" >&2; exit 1 ;;
esac

if [ -z "${KCADM:-}" ]; then
  KC_POD="${KC_POD:-keycloak-keycloakx-0}"
  KC_NS="${KC_NS:-keycloak}"
  KCADM="kubectl -n $KC_NS exec $KC_POD -- /opt/keycloak/bin/kcadm.sh"
  KC_ADMIN_PW="$(kubectl -n "$KC_NS" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
  $KCADM config credentials --server http://localhost:8080/auth --realm master --user admin --password "$KC_ADMIN_PW"
fi

# Pull one execution out of a flow's execution list by provider id (or, for sub-flows, by
# display-name suffix -- stock names differ across Keycloak releases, e.g. 26.3 renamed
# "Browser - Conditional OTP" to "Browser - Conditional 2FA", so match on what is stable).
exec_json() {  # <flow alias> <python predicate over e>
  $KCADM get "authentication/flows/$1/executions" -r "$REALM" | PRED="$2" python3 -c "
import json, os, sys
pred = os.environ['PRED']
m = [e for e in json.load(sys.stdin) if eval(pred, {}, {'e': e})]
if len(m) != 1:
    sys.exit(f'expected exactly one execution matching: {pred} (found {len(m)})')
print(json.dumps(m[0]))"
}
set_requirement() {  # <flow alias> <execution json> <requirement>
  echo "$2" | python3 -c "import json,sys; e=json.load(sys.stdin); e['requirement']='$3'; print(json.dumps(e))" \
    | $KCADM update "authentication/flows/$1/executions" -r "$REALM" -f -
}
urlenc() { python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$1"; }

echo "==> [1/4] Unbind and drop any previous $FLOW flow"
$KCADM update "realms/$REALM" -s browserFlow=browser
OLD_ID="$($KCADM get authentication/flows -r "$REALM" | python3 -c "
import json, sys
print(next((f['id'] for f in json.load(sys.stdin) if f['alias'] == '$FLOW'), ''))")"
if [ -n "$OLD_ID" ]; then $KCADM delete "authentication/flows/$OLD_ID" -r "$REALM"; fi

echo "==> [2/4] Realm role $ROLE, mapped onto: $([ "$MFA_MODE" = groups ] && echo "$MFA_GROUPS" || echo "(no groups -- mode $MFA_MODE)")"
$KCADM get "roles/$ROLE" -r "$REALM" >/dev/null 2>&1 || $KCADM create roles -r "$REALM" -s name="$ROLE" \
  -s "description=Members must use a second factor (managed by infrastructure/keycloak/configure-mfa.sh)"
for G in $($KCADM get "roles/$ROLE/groups" -r "$REALM" | python3 -c "import json,sys; print(' '.join(g['name'] for g in json.load(sys.stdin)))"); do
  $KCADM remove-roles -r "$REALM" --gname "$G" --rolename "$ROLE"
done
if [ "$MFA_MODE" = groups ]; then
  for G in ${MFA_GROUPS//,/ }; do $KCADM add-roles -r "$REALM" --gname "$G" --rolename "$ROLE"; done
fi

if [ "$MFA_MODE" = optional ]; then
  echo "==> [3/4] optional: leaving the stock browser flow bound"
  echo "==> [4/4] Done -- OTP only for users who enrolled one themselves"
  exit 0
fi

echo "==> [3/4] Build $FLOW from a fresh copy of the stock browser flow ($MFA_MODE)"
$KCADM create authentication/flows/browser/copy -r "$REALM" -s newName="$FLOW"
SUBFLOW="$(exec_json "$FLOW" "e.get('authenticationFlow') and e['displayName'].endswith(('Conditional 2FA', 'Conditional OTP'))")"
SUBFLOW_ALIAS="$(urlenc "$(echo "$SUBFLOW" | python3 -c "import json,sys; print(json.load(sys.stdin)['displayName'])")")"
# Stock: REQUIRED "user configured" condition, i.e. OTP only for the already-enrolled. Both
# enforcing modes drop it -- an unenrolled user must be made to enrol, not skipped.
set_requirement "$SUBFLOW_ALIAS" "$(exec_json "$SUBFLOW_ALIAS" "e.get('providerId') == 'conditional-user-configured'")" DISABLED
set_requirement "$SUBFLOW_ALIAS" "$(exec_json "$SUBFLOW_ALIAS" "e.get('providerId') == 'auth-otp-form'")" REQUIRED
if [ "$MFA_MODE" = all ]; then
  set_requirement "$FLOW" "$SUBFLOW" REQUIRED
else
  $KCADM create "authentication/flows/$SUBFLOW_ALIAS/executions/execution" -r "$REALM" -s provider=conditional-user-role
  ROLE_COND="$(exec_json "$SUBFLOW_ALIAS" "e.get('providerId') == 'conditional-user-role'")"
  set_requirement "$SUBFLOW_ALIAS" "$ROLE_COND" REQUIRED
  ROLE_COND_ID="$(echo "$ROLE_COND" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
  $KCADM create "authentication/executions/$ROLE_COND_ID/config" -r "$REALM" \
    -s alias=mfa-required-role -s "config.condUserRole=$ROLE"
fi

echo "==> [4/4] Bind $FLOW as the realm's browser flow"
$KCADM update "realms/$REALM" -s browserFlow="$FLOW"
$KCADM get "authentication/flows/$FLOW/executions" -r "$REALM" | python3 -c "
import json, sys
for e in json.load(sys.stdin):
    print('  ' * e['level'] + f\"{e['requirement']:<12} {e['displayName']}\")"
