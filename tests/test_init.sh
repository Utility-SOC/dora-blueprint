#!/usr/bin/env bash
# `make init` end to end, on a throwaway copy of this checkout: the promise that anyone can
# turn a fork into their own working instance. Checks every secret decrypts with the NEW key and
# parses the way bootstrap/install.sh reads it, the new PKI chain verifies and matches its key,
# the LDAP seed hashes match the new passwords, and no old identity is left in config.
# Needs age, sops, openssl, python3 (CI installs them; `make test` skips this without them).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Copy the working tree (uncommitted changes included) and make it a clean repo of its own.
mkdir "$T/repo"
(cd "$REPO" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf -) \
  | tar -xf - -C "$T/repo"
cd "$T/repo"
git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base

source platform.env
OLD_HOST="$PLATFORM_HOST"; OLD_REPO="$REPO_URL"
HOME="$T/home" NEW_REPO_URL=https://github.com/example/dora-blueprint.git NEW_PLATFORM_HOST=10.99.0.7 \
  bash bootstrap/init.sh > "$T/init.log" 2>&1 || { cat "$T/init.log"; fail "init.sh exited non-zero"; }
export SOPS_AGE_KEY_FILE="$T/home/.config/sops/age/keys.txt"

for f in $(git ls-files '*.enc.yaml'); do
  sops -d "$f" > /dev/null || fail "$f doesn't decrypt with the new key"
done
grep -q "$(age-keygen -y "$SOPS_AGE_KEY_FILE")" .sops.yaml || fail ".sops.yaml not pointed at the new key"

IAM="$(sops -d infrastructure/keycloak/secrets/iam-secrets.enc.yaml)"
for k in ldap_bind_password keycloak_admin_password argocd_oidc_client_secret minio_oidc_client_secret; do
  V="$(echo "$IAM" | awk "/^$k:/ {print \$2}")"   # install.sh's own parsing
  [ ${#V} -ge 32 ] || fail "$k missing or short as install.sh reads it: '$V'"
done

sops -d infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml > "$T/ca.yaml"
awk '/^tls_crt:/{f=1;next} /^tls_key:/{f=0} f' "$T/ca.yaml" | sed 's/^    //' > "$T/crt.pem"
awk '/^tls_key:/{f=1;next} f' "$T/ca.yaml" | sed 's/^    //' > "$T/key.pem"
[ "$(grep -c 'BEGIN CERTIFICATE' "$T/crt.pem")" = 2 ] || fail "issuer secret tls_crt isn't the 2-cert chain"
CA=infrastructure/cert-manager/ca-certs
openssl verify -CAfile "$CA/root-ca.crt" "$CA/intermediate-ca.crt" > /dev/null || fail "new chain doesn't verify"
[ "$(openssl x509 -in "$T/crt.pem" -noout -pubkey)" = "$(openssl pkey -in "$T/key.pem" -pubout)" ] \
  || fail "issuer key doesn't match issuer cert"
git diff --quiet HEAD -- "$CA/root-ca.crt" && fail "root CA wasn't regenerated"
ls "$T/home/.dora-blueprint/pki/"root-ca-*.key > /dev/null || fail "root key not written outside the repo"
git ls-files --others | grep -q '\.key$' && fail "a private key landed inside the repo"

echo "$IAM" | python3 -c '
import base64, hashlib, re, sys, yaml
sec = yaml.safe_load(sys.stdin)
seed = open("infrastructure/openldap/seed-ldif.yaml").read()
for user in ("alice", "bob", "utility"):
    h = re.search(rf"dn: cn={user},ou=people,[^\n]*\n(?:[ \t]+[^\n]*\n)*?[ \t]+userPassword: \{{SSHA\}}(\S+)", seed).group(1)
    raw = base64.b64decode(h)
    assert hashlib.sha1(str(sec[f"{user}_password"]).encode() + raw[20:]).digest() == raw[:20], user
' || fail "LDAP seed hashes don't match the new passwords"

python3 -c '
import yaml
cm = yaml.safe_load(open("drills/templates/platform-ca-configmap.yaml"))
assert cm["data"]["ca-chain.crt"] == open("infrastructure/cert-manager/ca-certs/ca-chain.crt").read()
' || fail "drill CA ConfigMap doesn't carry the new chain"

LEFT="$(git grep -lF -e "$OLD_REPO" -e "$OLD_HOST" -- apps bootstrap infrastructure drills canary ':!bootstrap/init.sh' || true)"
[ -z "$LEFT" ] || fail "old identity still in: $LEFT"
git diff --quiet HEAD -- docs CHANGELOG.md || fail "init touched docs/ or CHANGELOG.md"
grep -q '^PLATFORM_HOST=10.99.0.7$' platform.env || fail "platform.env not updated"

echo "init: OK"
