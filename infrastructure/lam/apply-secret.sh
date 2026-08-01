#!/usr/bin/env bash
# Creates/updates the lam-secrets k8s Secret from the shared iam-secrets.enc.yaml (the same
# SOPS file every other IAM-adjacent credential in this repo lives in) -- kept as its own small
# script rather than folded into bootstrap/install.sh's already-large secrets block, matching
# how persist-operator-credentials.sh is its own script too.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAM_PW="$(sops --decrypt "$REPO_ROOT/infrastructure/keycloak/secrets/iam-secrets.enc.yaml" | awk '/^lam_master_password:/ {print $2}')"

kubectl -n lam create secret generic lam-secrets \
  --from-literal=lamMasterPassword="$LAM_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "lam-secrets applied."
