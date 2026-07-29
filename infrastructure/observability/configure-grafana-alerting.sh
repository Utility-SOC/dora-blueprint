#!/usr/bin/env bash
# Phase 9 (Detection): creates the Grafana service account + API token the ns-restore drill
# workflow uses to read real alert state (t_detect) from Grafana's Alerting API. A token
# can't be file-provisioned the way a datasource or alert rule can -- it's server-side
# secret material Grafana generates once, via the API, after Grafana is actually up. Same
# "declarative infra, plus one script run once the service exists" shape as
# infrastructure/keycloak/configure-realm.sh, for the same reason.
#
# Viewer role only -- this account only ever reads alert state, never writes anything.
#
# Idempotent-ish, same discipline as configure-realm.sh: re-running against an
# already-created service account fails loudly (409) rather than silently reusing it --
# delete the service account first (`curl -X DELETE .../api/serviceaccounts/<id>`) to
# regenerate. The printed token is shown by Grafana exactly once; it isn't recoverable
# after this script exits, so it must be captured and SOPS-encrypted
# (infrastructure/observability/secrets/grafana-api-token.enc.yaml) before moving on.
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-https://192.168.1.106:9082}"
GRAFANA_NS="${GRAFANA_NS:-observability}"

echo "==> [1/3] Admin credentials"
GRAFANA_USER="$(kubectl -n "$GRAFANA_NS" get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d)"
GRAFANA_PASS="$(kubectl -n "$GRAFANA_NS" get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"

echo "==> [2/3] Create a Viewer-scoped service account"
SA_ID="$(curl -sk -u "$GRAFANA_USER:$GRAFANA_PASS" -X POST "$GRAFANA_URL/api/serviceaccounts" \
  -H 'Content-Type: application/json' \
  -d '{"name":"drill-detection-reader","role":"Viewer"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

echo "==> [3/3] Create a token for it"
TOKEN="$(curl -sk -u "$GRAFANA_USER:$GRAFANA_PASS" -X POST "$GRAFANA_URL/api/serviceaccounts/$SA_ID/tokens" \
  -H 'Content-Type: application/json' \
  -d '{"name":"drill-detection-token"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')"

echo "Service account id: $SA_ID"
echo "Token (Grafana shows this exactly once -- SOPS-encrypt it now into"
echo "infrastructure/observability/secrets/grafana-api-token.enc.yaml, key grafana_api_token):"
echo "$TOKEN"
