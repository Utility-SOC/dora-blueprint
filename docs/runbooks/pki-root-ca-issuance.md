# Runbook: offline Root CA issuance, and Intermediate CA (re-)signing

This is the actual, reproducible process used to generate this platform's PKI root of trust —
not a description of what a real deployment *should* do, but the exact commands run against
appserv to produce the certificates `infrastructure/cert-manager/` depends on. Real, citable
evidence for ISO A.8.24 (cryptography) and A.5.31 (legal/regulatory requirements around
cryptographic controls) per `docs/05-shared-responsibility.md`.

## Design

- **Root CA**: RSA 4096, 10-year validity. Self-signed. Private key is generated inside, and
  never leaves, an isolated environment — see "Isolation model" below. Used exactly once per
  ~5 years: to sign the Intermediate CA.
- **Intermediate CA**: RSA 4096, 5-year validity, signed by the Root. **This** is what actually
  issues leaf certificates day to day, via cert-manager's `ca`-type `ClusterIssuer` — imported
  into the cluster as a SOPS-encrypted secret (`infrastructure/cert-manager/secrets/
  intermediate-ca.enc.yaml`). Rotated at the **4-year-11-month** mark: run this same process
  again (skipping Root CA generation — the existing Root signs a fresh Intermediate), well
  before the current Intermediate expires, so there's no gap.
- **Chain file** (`ca-chain.crt`): Intermediate cert followed by Root cert, concatenated. This
  is what cert-manager's `ClusterIssuer` secret's `tls.crt` actually contains — leaf certs need
  the full chain to verify back to a client's trusted Root, not just the immediate issuer.

## Isolation model — a Docker container, not a literal hypervisor VM

Earlier conversation described this pattern as "a throwaway VM on appserv" — implemented here as
a Docker container instead, for a concrete reason: appserv has no `virt-install`/`qemu`/`kvm-ok`
installed, only Docker (which the entire rest of this lab already runs on). Standing up a full
KVM/libvirt hypervisor solely to generate one root key pair would be disproportionate
infrastructure for what the security property actually requires. The property that matters —
an environment created, used once, then made inaccessible, that never touches the cluster's own
network — is what a container running with `--network none` provides:

```
docker run -d --name pki-root-ca --network none --entrypoint /bin/sh \
  -v ~/pki-root-ca:/pki alpine/openssl:latest -c "sleep infinity"
```

`--network none` gives the container only a loopback interface — confirmed directly
(`docker exec pki-root-ca ip addr` showed nothing but `lo`), not assumed from the flag name.

**A real gotcha hit while building this**: the first attempt used a bind-mounted volume
(`-v ~/pki-root-ca:/pki`) for *all* generated files, including the Root CA's private key. A
bind mount means the "isolated" container's files are still sitting in a plain, host-readable
directory the whole time — stopping the container does nothing to protect a key that was never
actually inside it, only inside a directory it happened to have mounted. Fixed by moving
`root-ca.key` into the container's own writable layer (`/root/sealed/root-ca.key`, *not* under
`/pki`) once generated, and confirming it no longer appears in the host-visible bind-mount
directory. Only the Root CA's **certificate** (public, non-sensitive) and the Intermediate CA's
cert+key (extracted once, for SOPS encryption, then deleted from the host) live under the bind
mount.

A second, minor gotcha: `alpine:3.20` (the base image originally pulled) doesn't ship `openssl`,
and `--network none` means there's no way to `apk add` it after the fact — genuinely offline
means no mid-flight package installation either. Fixed by using `alpine/openssl`, a pre-built
image with OpenSSL already included, so no network access is ever needed once the container is
running.

## Commands actually run

```bash
# 1. Root CA — RSA 4096, 10 years, self-signed.
docker exec pki-root-ca sh -c '
cd /pki
cat > root-ca-ext.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no
[req_distinguished_name]
C = IE
O = Resilience Lab
OU = Platform PKI
CN = Resilience Lab Root CA
[v3_ca]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF
openssl genrsa -out root-ca.key 4096
openssl req -x509 -new -nodes -key root-ca.key -sha256 -days 3650 \
  -out root-ca.crt -config root-ca-ext.cnf -extensions v3_ca
'

# 2. Move the Root CA private key out of the bind mount, into the container's own
#    filesystem layer -- the fix for the bind-mount gotcha above.
docker exec pki-root-ca sh -c 'mkdir -p /root/sealed && mv /pki/root-ca.key /root/sealed/root-ca.key && chmod 600 /root/sealed/root-ca.key'

# 3. Intermediate CA — RSA 4096, 5 years, signed by the Root, pathlen:0 (cannot itself
#    sign further intermediates).
docker exec pki-root-ca sh -c '
cd /pki
cat > intermediate-csr.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
C = IE
O = Resilience Lab
OU = Platform PKI
CN = Resilience Lab Intermediate CA
EOF
cat > intermediate-ext.cnf <<EOF
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
openssl genrsa -out intermediate-ca.key 4096
openssl req -new -key intermediate-ca.key -sha256 -out intermediate-ca.csr -config intermediate-csr.cnf
openssl x509 -req -in intermediate-ca.csr -CA root-ca.crt -CAkey /root/sealed/root-ca.key \
  -CAcreateserial -out intermediate-ca.crt -days 1825 -sha256 -extfile intermediate-ext.cnf
'

# 4. Build the chain file and verify it actually validates before trusting it.
docker exec pki-root-ca sh -c 'cd /pki && cat intermediate-ca.crt root-ca.crt > ca-chain.crt'
docker exec pki-root-ca openssl verify -CAfile /pki/root-ca.crt /pki/intermediate-ca.crt
# -> intermediate-ca.crt: OK

# 5. Extract the Intermediate cert+key and the chain file for SOPS encryption (see
#    infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml), then delete the
#    plaintext intermediate key from appserv's disk -- it only needs to exist locally
#    long enough to be encrypted.
scp appserv:~/pki-root-ca/{root-ca.crt,intermediate-ca.crt,intermediate-ca.key,ca-chain.crt} ./
ssh appserv 'rm -f ~/pki-root-ca/intermediate-ca.key ~/pki-root-ca/intermediate-ca.csr ~/pki-root-ca/*.cnf ~/pki-root-ca/root-ca.srl'

# 6. Shelve the container -- stopped, not removed, so it can be started again in
#    ~4y11m to sign the next Intermediate without regenerating the Root.
docker stop pki-root-ca
```

## Verification performed

- `openssl x509 -in root-ca.crt -noout -subject -issuer -dates` — subject equals issuer
  (self-signed), `notAfter` is 10 years out.
- `openssl x509 -in intermediate-ca.crt -noout -subject -issuer -dates` — issuer is the Root's
  subject, `notAfter` is 5 years out.
- `openssl verify -CAfile root-ca.crt intermediate-ca.crt` returned `OK` — the chain actually
  validates, not just "the commands didn't error."
- `docker exec pki-root-ca ip addr` showed only the loopback interface before any key material
  was generated — the isolation claim checked directly, not assumed from the `--network none`
  flag.
- After extraction: `ls ~/pki-root-ca/` on appserv shows only the three public certificates
  (`root-ca.crt`, `intermediate-ca.crt`, `ca-chain.crt`) — confirmed no private key material
  remains in a plaintext, host-readable location.

## Rotation (4 years 11 months from now)

1. `docker start pki-root-ca` — the same container, still holding the Root CA key in its own
   filesystem layer (Docker containers persist their writable layer across stop/start; this was
   not re-verified against real time yet, since it hasn't been ~5 years — noted as an assumption
   to confirm when this actually runs).
2. Generate a fresh Intermediate CA key/CSR, sign it with the still-sealed Root CA key exactly as
   in step 3 above.
3. Extract, SOPS-encrypt, replace `infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml`,
   commit, `bootstrap/install.sh` (or a targeted re-run of its cert-manager secret step) rotates
   the live cluster secret, cert-manager re-issues all leaf certs from the new Intermediate.
4. `docker stop pki-root-ca` again.
