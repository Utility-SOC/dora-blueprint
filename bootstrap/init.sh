#!/usr/bin/env bash
# `make init` -- turns a fresh clone/fork of this repo into *your* instance of it.
#
# Everything this repo needs that is specific to one deployment lives in two places:
# platform.env (non-secret identity: repo URL, UI host, age recipient, PKI subject) and the
# SOPS-encrypted *.enc.yaml files (every credential). Without this script a fork inherits the
# upstream values, and the upstream secrets are encrypted to an age key the fork doesn't hold,
# so nothing past `talosctl cluster create` can work. This script, in one pass:
#
#   1. uses (or creates) your age key and points .sops.yaml at it
#   2. generates a fresh offline Root CA + Intermediate CA (docs/runbooks/pki-root-ca-issuance.md's
#      exact extensions and lifetimes); the Root key is written OUTSIDE the repo
#   3. generates every credential from scratch and re-encrypts every *.enc.yaml to your key
#      (incl. matching SSHA hashes in the LDAP seed, so the demo users can actually log in)
#   4. a deploy key, only if REPO_URL is SSH (a public https fork needs no Argo CD credential)
#   5. rewrites the old REPO_URL / PLATFORM_HOST to the new ones across config and scripts --
#      never under docs/ or in CHANGELOG.md, which record what happened on the original
#      instance, and never inside evidence
#
# Usage:  make init REPO_URL=https://github.com/<you>/dora-blueprint.git PLATFORM_HOST=10.0.0.5
# Any variable left unset keeps platform.env's current value. Needs: age, sops, openssl,
# ssh-keygen (SSH REPO_URL only), python3, git. Refuses to run on a dirty tree so that
# `git checkout .` is always a complete undo.
#
# Not regenerated, because only the running service can issue them: the Grafana and GLPI API
# tokens. They're written empty; infrastructure/observability/configure-grafana-alerting.sh and
# infrastructure/glpi/configure-glpi.sh print them once those services are up (same as the
# original build -- see bootstrap/install.sh steps 12 and 14).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

for bin in age age-keygen sops openssl python3 git; do
  command -v "$bin" >/dev/null || { echo "missing required binary: $bin" >&2; exit 1; }
done
if [ -n "$(git status --porcelain)" ] && [ "${INIT_ALLOW_DIRTY:-}" != 1 ]; then
  echo "working tree not clean -- commit or stash first, so 'git checkout .' can undo this run" >&2
  exit 1
fi

# shellcheck source=../platform.env
source platform.env
OLD_REPO_URL="$REPO_URL"; OLD_PLATFORM_HOST="$PLATFORM_HOST"
NEW_REPO_URL="${NEW_REPO_URL:-$OLD_REPO_URL}"
NEW_PLATFORM_HOST="${NEW_PLATFORM_HOST:-$OLD_PLATFORM_HOST}"
AGE_KEY_FILE="${AGE_KEY_FILE:-${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}}"
PKI_DIR="${PKI_DIR:-$HOME/.dora-blueprint/pki}"
WORK="$(mktemp -d)"
trap 'find "$WORK" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$WORK"' EXIT

echo "==> [1/5] age key ($AGE_KEY_FILE)"
if [ ! -f "$AGE_KEY_FILE" ]; then
  mkdir -p "$(dirname "$AGE_KEY_FILE")"
  age-keygen -o "$AGE_KEY_FILE" 2>/dev/null
  chmod 600 "$AGE_KEY_FILE"
  echo "    created -- back this file up; without it no secret in your repo can be decrypted"
fi
RECIPIENT="$(age-keygen -y "$AGE_KEY_FILE" | head -1)"
echo "    recipient: $RECIPIENT"
# .sops.yaml first: every encryption below goes through its creation rules, same as any
# later hand-run `sops --encrypt` in this repo would.
python3 -c 'import re, sys; p = ".sops.yaml"; t = open(p).read()
open(p, "w").write(re.sub(r"(?m)^(\s+age: ).*$", lambda m: m.group(1) + sys.argv[1], t))' "$RECIPIENT"

echo "==> [2/5] Offline Root CA + Intermediate CA (Root key -> $PKI_DIR, never the repo)"
mkdir -p "$PKI_DIR"; chmod 700 "$PKI_DIR"
cat > "$WORK/root.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
C = $PKI_COUNTRY
O = $PKI_ORG
OU = Platform PKI
CN = $PKI_ORG Root CA
[v3_ca]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF
cat > "$WORK/int-csr.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
C = $PKI_COUNTRY
O = $PKI_ORG
OU = Platform PKI
CN = $PKI_ORG Intermediate CA
EOF
cat > "$WORK/int-ext.cnf" <<EOF
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
STAMP="$(date -u +%Y%m%d%H%M%S)"
ROOT_KEY="$PKI_DIR/root-ca-$STAMP.key"
openssl genrsa -out "$ROOT_KEY" 4096 2>/dev/null; chmod 600 "$ROOT_KEY"
openssl req -x509 -new -nodes -key "$ROOT_KEY" -sha256 -days 3650 -config "$WORK/root.cnf" \
  -out "$WORK/root-ca.crt"
openssl genrsa -out "$WORK/intermediate-ca.key" 4096 2>/dev/null
openssl req -new -key "$WORK/intermediate-ca.key" -sha256 -config "$WORK/int-csr.cnf" -out "$WORK/int.csr"
openssl x509 -req -in "$WORK/int.csr" -CA "$WORK/root-ca.crt" -CAkey "$ROOT_KEY" -CAcreateserial \
  -CAserial "$WORK/root.srl" -days 1825 -sha256 -extfile "$WORK/int-ext.cnf" \
  -out "$WORK/intermediate-ca.crt" 2>/dev/null
openssl verify -CAfile "$WORK/root-ca.crt" "$WORK/intermediate-ca.crt" >/dev/null
CA_DIR=infrastructure/cert-manager/ca-certs
cp "$WORK/root-ca.crt" "$CA_DIR/root-ca.crt"
cp "$WORK/intermediate-ca.crt" "$CA_DIR/intermediate-ca.crt"
cat "$WORK/intermediate-ca.crt" "$WORK/root-ca.crt" > "$CA_DIR/ca-chain.crt"
echo "    root key: $ROOT_KEY -- move it offline; it's only needed to re-sign the Intermediate"

echo "==> [3/5] Fresh credentials, encrypted to $RECIPIENT"
pw() { openssl rand -hex 20; }
enc() {  # <target> -- plaintext YAML on stdin
  sops --encrypt --filename-override "$1" /dev/stdin > "$1.tmp"
  mv "$1.tmp" "$1"
}
ALICE_PW="$(pw)"; BOB_PW="$(pw)"; UTILITY_PW="$(pw)"
# tls_crt is the full chain (Intermediate, then Root) -- what bootstrap/install.sh step 7 loads
# into cert-manager's issuer secret, so leaf certs verify all the way back to the Root.
python3 - "$CA_DIR/ca-chain.crt" "$WORK/intermediate-ca.key" > "$WORK/ca.yaml" <<'EOF'
import sys
crt, key = (open(p).read() for p in sys.argv[1:3])
indent = lambda s: "".join(f"    {line}\n" for line in s.splitlines())
print(f"tls_crt: |\n{indent(crt)}tls_key: |\n{indent(key)}", end="")
EOF
enc infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml < "$WORK/ca.yaml"
enc infrastructure/keycloak/secrets/iam-secrets.enc.yaml <<EOF
ldap_bind_password: $(pw)
argocd_oidc_client_secret: $(pw)
grafana_oidc_client_secret: $(pw)
alice_password: $ALICE_PW
bob_password: $BOB_PW
keycloak_admin_password: $(pw)
minio_oidc_client_secret: $(pw)
keycloak_master_utility_password: $(pw)
utility_password: $UTILITY_PW
keycloak_postgres_password: $(pw)
lam_master_password: $(pw)
EOF
enc infrastructure/velero/secrets/minio-root-credentials.enc.yaml <<EOF
rootUser: minio-admin
rootPassword: $(pw)
EOF
enc infrastructure/glpi/secrets/glpi-secrets.enc.yaml <<EOF
mariadb_root_password: $(pw)
glpi_db_password: $(pw)
EOF
echo 'grafana_api_token:' | enc infrastructure/observability/secrets/grafana-api-token.enc.yaml
echo 'glpi_api_token:' | enc infrastructure/glpi/secrets/glpi-api-token.enc.yaml
# LDAP seed holds salted SHA-1 (SSHA) hashes, the format OpenLDAP's userPassword expects.
ALICE_PW="$ALICE_PW" BOB_PW="$BOB_PW" UTILITY_PW="$UTILITY_PW" python3 - <<'EOF'
import base64, hashlib, os, re
path = "infrastructure/openldap/seed-ldif.yaml"
text = open(path).read()
def ssha(pw):
    salt = os.urandom(8)
    return "{SSHA}" + base64.b64encode(hashlib.sha1(pw.encode() + salt).digest() + salt).decode()
for user in ("alice", "bob", "utility"):
    pattern = rf"(dn: cn={user},ou=people,[^\n]*\n(?:[ \t]+[^\n]*\n)*?[ \t]+userPassword: )\S+"
    text, n = re.subn(pattern, lambda m: m.group(1) + ssha(os.environ[f"{user.upper()}_PW"]), text)
    assert n == 1, f"seed-ldif: expected one userPassword for {user}, found {n}"
open(path, "w").write(text)
EOF
python3 - "$WORK/root-ca.crt" "$WORK/intermediate-ca.crt" <<'EOF'
import re, sys
path = "drills/templates/platform-ca-configmap.yaml"
chain = open(sys.argv[2]).read() + open(sys.argv[1]).read()
text = open(path).read()
head, sep, _ = text.partition("  ca-chain.crt: |\n")
assert sep, "platform-ca-configmap.yaml: ca-chain.crt key not found"
open(path, "w").write(head + sep + "".join(f"    {line}\n" for line in chain.splitlines()))
EOF

echo "==> [4/5] Argo CD repository credential"
case "$NEW_REPO_URL" in
  git@*|ssh://*)
    ssh-keygen -q -t ed25519 -N "" -C "argocd@dora-blueprint" -f "$WORK/deploy"
    { echo "argocd_ssh_private_key: |"; sed 's/^/    /' "$WORK/deploy"; } \
      | enc bootstrap/secrets/argocd-repo-key.enc.yaml
    echo "    add this as a read-only deploy key on your repository:"
    echo "    $(cat "$WORK/deploy.pub")"
    ;;
  *)
    echo 'argocd_ssh_private_key:' | enc bootstrap/secrets/argocd-repo-key.enc.yaml
    echo "    https repo -- Argo CD reads it anonymously, no credential (the repo must be public)"
    ;;
esac

echo "==> [5/5] Rewriting instance identity outside docs/ and CHANGELOG.md"
python3 - "$OLD_REPO_URL" "$NEW_REPO_URL" "$OLD_PLATFORM_HOST" "$NEW_PLATFORM_HOST" "$RECIPIENT" <<'EOF'
import re, subprocess, sys
old_repo, new_repo, old_host, new_host, recipient = sys.argv[1:]
files = subprocess.run(["git", "ls-files", "apps", "bootstrap", "infrastructure", "drills", "canary"],
                       capture_output=True, text=True, check=True).stdout.split()
# Match the host only as a whole address -- 10.0.0.1 must not hit 10.0.0.10.
host_re = re.compile(rf"(?<![\w.]){re.escape(old_host)}(?![\w.])")
changed = 0
for f in files:
    if f.endswith(".enc.yaml") or f == "bootstrap/init.sh":
        continue
    try:
        text = open(f).read()
    except UnicodeDecodeError:
        continue
    new = host_re.sub(new_host, text.replace(old_repo, new_repo)) if old_host != new_host else text.replace(old_repo, new_repo)
    if new != text:
        open(f, "w").write(new)
        changed += 1
env = open("platform.env").read()
env = re.sub(r"(?m)^REPO_URL=.*$", f"REPO_URL={new_repo}", env)
env = re.sub(r"(?m)^PLATFORM_HOST=.*$", f"PLATFORM_HOST={new_host}", env)
env = re.sub(r"(?m)^SOPS_AGE_RECIPIENT=.*$", f"SOPS_AGE_RECIPIENT={recipient}", env)
open("platform.env", "w").write(env)
print(f"    {changed} files rewritten")
EOF

cat <<EOF

Done. Review with 'git diff', then commit and push to $NEW_REPO_URL.
Next: make lab-core (or lab-full). Demo user passwords are in
infrastructure/keycloak/secrets/iam-secrets.enc.yaml:  sops -d <that file>
EOF
