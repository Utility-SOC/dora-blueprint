#!/usr/bin/env bash
# One-time MinIO OIDC client setup — mirrors configure-realm.sh's argocd/grafana client
# block exactly, added separately (not folded into configure-realm.sh itself) since it
# runs later, against a realm that already exists, rather than as part of initial realm
# creation.
#
# MinIO's own OIDC config (apps/minio.yaml's `oidc:` block) uses `claimName: groups` --
# same "the IdP just asserts group membership, each consuming app maps it locally"
# pattern already used for Argo CD's policy.csv and Grafana's role mapping, not a
# MinIO-specific "policy" claim baked into the token. Group -> policy binding itself
# happens via `mc admin policy attach ... --group=` after MinIO restarts with OIDC
# enabled -- see this script's final step.
#
# Idempotent-ish, same discipline as configure-realm.sh: re-running fails loudly on the
# client already existing rather than silently no-op'ing.
set -euo pipefail

KC_POD="${KC_POD:-keycloak-keycloakx-0}"
KC_NS="${KC_NS:-keycloak}"
KCADM="kubectl -n $KC_NS exec $KC_POD -- /opt/keycloak/bin/kcadm.sh"

echo "==> [1/4] Login as bootstrap admin"
KC_ADMIN_PW="$(kubectl -n "$KC_NS" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)"
$KCADM config credentials --server http://localhost:8080/auth --realm master --user admin --password "$KC_ADMIN_PW"

echo "==> [2/4] Create the minio client (a real random secret, printed once below)"
MINIO_SECRET="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
$KCADM create clients -r platform \
  -s clientId=minio -s enabled=true -s protocol=openid-connect -s publicClient=false \
  -s clientAuthenticatorType=client-secret -s secret="$MINIO_SECRET" \
  -s 'redirectUris=["http://192.168.1.106:9084/oauth_callback", "https://192.168.1.106:9084/oauth_callback"]' \
  -s standardFlowEnabled=true -s directAccessGrantsEnabled=false

echo "==> [3/4] Groups claim mapper (same shape as argocd/grafana's own)"
CID="$($KCADM get clients -r platform -q clientId=minio --fields id --format csv --noquotes)"
$KCADM create "clients/$CID/protocol-mappers/models" -r platform \
  -s name=groups -s protocol=openid-connect -s protocolMapper=oidc-group-membership-mapper \
  -s 'config."full.path"="false"' \
  -s 'config."id.token.claim"="true"' \
  -s 'config."access.token.claim"="true"' \
  -s 'config."userinfo.token.claim"="true"' \
  -s 'config."claim.name"="groups"'

echo "==> [4/4] Done"
echo
echo "MinIO OIDC client secret (SOPS-encrypt this now into"
echo "infrastructure/keycloak/secrets/iam-secrets.enc.yaml, key minio_oidc_client_secret --"
echo "Keycloak never shows this again):"
echo "$MINIO_SECRET"
echo
echo "Next steps, in order:"
echo "  1. Add minio_oidc_client_secret to iam-secrets.enc.yaml (re-encrypt, commit)."
echo "  2. Re-run bootstrap/install.sh so step 8 applies the new minio-oidc-secret K8s Secret."
echo "  3. Let Argo CD sync apps/minio.yaml (already has the oidc: block referencing that"
echo "     secret) -- MinIO restarts with OIDC enabled."
echo "  4. Attach policies to the new LDAP groups (requires the minio/mc image -- not bundled"
echo "     in minio/minio itself):"
echo '     kubectl -n velero run mc-tmp --image=minio/mc --restart=Never --command -- sleep 3600'
echo '     kubectl -n velero wait --for=condition=Ready pod/mc-tmp --timeout=60s'
echo '     MINIO_ROOT_USER=$(kubectl -n velero get secret minio-root-credentials -o jsonpath="{.data.rootUser}" | base64 -d)'
echo '     MINIO_ROOT_PASSWORD=$(kubectl -n velero get secret minio-root-credentials -o jsonpath="{.data.rootPassword}" | base64 -d)'
echo '     kubectl -n velero exec mc-tmp -- mc alias set local http://minio.velero.svc.cluster.local:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"'
echo '     kubectl -n velero exec mc-tmp -- mc admin policy attach local consoleAdmin --group=minio-admins'
echo '     kubectl -n velero exec mc-tmp -- mc admin policy attach local readonly --group=minio-viewers'
echo '     kubectl -n velero delete pod mc-tmp'
echo "  5. Verify: log into http://192.168.1.106:9084 via Keycloak as utility (expect full"
echo "     console access) and as bob (expect read-only) -- checked directly against the live"
echo "     UI/API, not assumed from the policy attachment succeeding."
