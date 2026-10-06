# Track 01: ephemeral secrets and PKI

**Decision (owner, 2026-10-06):** this is a demo and a teaching tool. Every stand-up generates its
own certificate authority and its own credentials. No secret material lives in Git, and destroying the
VM destroys everything. This replaces the SOPS + age model, which tied every stand-up to one person's
key. That key was lost once (gap G16), and the public CA certs have already drifted from the
re-issued CA: `infrastructure/cert-manager/ca-certs/*.crt` still carries the 2026-07-29 certificates.

The production pattern (offline root, HSM, external secrets manager) is still *taught* (T02c). It just isn't
what the lab runs.

**Order:** T02a → T02b → T02c, each its own PR, after PR #1–#4 are merged. T02a and T02b get a review from a
stronger model before merging, because subtle mistakes in credential handling are cheap to make and costly to miss.

---

## T02a · Generate the PKI in-cluster with cert-manager

- **Wave / mode:** 1 · offline, with a live proof in T17
- **Depends on:** D1
- **Why:** remove the committed CA material and the drift it causes, while keeping a real two-tier chain
  (root → intermediate → leaf) so TLS still teaches something.

**Read first:** `infrastructure/cert-manager/` (all of it), `apps/core/cert-manager*.yaml` (sync waves 0, 1, 2),
`docs/runbooks/pki-root-ca-issuance.md`, `drills/templates/platform-ca-configmap.yaml` and the three
drill templates that mount it (`grep -l platform-ca drills/templates/*.yaml`). They `curl --cacert
/etc/platform-ca/ca-chain.crt`, so the key name matters. Also read `bootstrap/install.sh` step 7 and
cert-manager's "CA issuer bootstrapping" documentation.

**Files:**
- Delete `infrastructure/cert-manager/ca-certs/`, `infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml`
  and `drills/templates/platform-ca-configmap.yaml`.
- New `infrastructure/cert-manager/bootstrap-ca/` holding the self-signed issuer, root Certificate,
  root ClusterIssuer and intermediate Certificate.
- New `apps/core/trust-manager.yaml` and `infrastructure/trust-manager/bundle.yaml`.
- Edit the `apps/core/cert-manager*.yaml` sync waves, `bootstrap/appproject-platform.yaml` (allow trust-manager
  kinds and namespace), the Cilium policies for the new namespace or pods, the three drill templates,
  `bootstrap/install.sh` (remove step 7), `Makefile` (add `ca-export`), and the docs listed below.

**Steps:**
1. `ClusterIssuer selfsigned-bootstrap` with `spec.selfSigned: {}` (sync wave 1).
2. `Certificate platform-root-ca` in namespace `cert-manager`: `isCA: true`, `commonName: Resilience Lab Root CA`,
   `subject.countries: [IE]`, `subject.organizations: [Resilience Lab]`, ECDSA P-384, `duration: 87600h`
   (10 years), `secretName: platform-root-ca`, issued by `selfsigned-bootstrap` (wave 2).
3. `ClusterIssuer platform-root` with `ca.secretName: platform-root-ca` (wave 3). cert-manager's
   cluster resource namespace is `cert-manager`; confirm that's where it looks for ClusterIssuer secrets.
4. `Certificate intermediate-ca`: `isCA: true`, ECDSA P-256, `duration: 43800h` (5 years), issued by
   `platform-root`, `secretName: intermediate-ca`, the **same name** the existing `ClusterIssuer
   platform-ca` already references (wave 4). Leave the existing issuer and all leaf `Certificate`s untouched
   except for moving them to wave 5 or later.
5. **trust-manager.** Pin the chart version in its own Argo CD Application (wave 2, before the Bundle). Add a
   `Bundle platform-ca` whose sources are the root's `ca.crt` from secret `platform-root-ca` plus the
   intermediate's `tls.crt` from secret `intermediate-ca`. Target a ConfigMap named `platform-ca` with key
   `ca-chain.crt` in namespaces labelled `platform.dora-blueprint/trust: "true"`, and add that label to
   `argo-workflows`, `observability` and any other namespace that needs it. The drill templates then keep
   working unchanged, but check them.
6. Pod Security: trust-manager must run under the restricted PSS profile. If it can't, follow P2 (exception file + risk
   acceptance). Add a default-deny Cilium policy plus the explicit allows it needs (kube-apiserver egress).
7. `make ca-export`: `kubectl -n cert-manager get secret platform-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/dora-blueprint-root-ca.crt`
   and print how to import it into macOS, Windows and Firefox trust stores.
8. Docs:
   - Rewrite `docs/runbooks/pki-root-ca-issuance.md` as "how the lab's CA is generated, and how a real
     firm would do it differently": offline root kept in an HSM or air-gapped; only the intermediate
     in-cluster; a root ceremony with witnesses; CRL/OCSP; rotation.
   - Update the PKI rows in `docs/03-control-matrix.md` and `docs/05-shared-responsibility.md`.
   - Add to `docs/04-limitations.md`: "the root CA is generated in-cluster and lives as long as the VM, on purpose."
   - Update the DORA sheet row `DORA-9-9(4)(d)`.
   - The historical `pki-chain-verification` evidence sample stays as it is.

**Tests** (`tests/test_pki_manifests.py`):
- No `BEGIN CERTIFICATE` or `BEGIN .*PRIVATE KEY` anywhere in the repo outside `docs/evidence/samples/`.
- Walk every `Certificate.spec.issuerRef` and every `ClusterIssuer.spec.ca.secretName` in the YAML. Each issuer
  must resolve to a `Certificate` producing that secret, ending at `selfsigned-bootstrap`, with no cycles.
- Sync-wave ordering: the self-signed issuer < root cert < root issuer < intermediate < `platform-ca` issuer < leaves.
- Every drill template that mounts `platform-ca` reads a key the Bundle produces.

**Done when:**
- [ ] The tests above pass, and no CA material remains in Git.
- [ ] `kubeconform` (pinned) or an equivalent schema check passes on all new manifests.
- [ ] The docs and the DORA sheet are updated. `make dora-coverage` re-rendered.
- [ ] The PR lists the live checks for T17: all `Certificate`s `Ready=True`;
  `openssl s_client -connect <host>:9082 -showcerts` shows leaf → intermediate → root; a drill's curl succeeds.

**Out of scope:** changing which services get leaf certs; ACME or Let's Encrypt; mTLS.

---

## T02b · Generate every credential at bootstrap

- **Wave / mode:** 1 · offline, with a live proof in T17
- **Depends on:** T02a merged

**Read first:** `bootstrap/install.sh` steps 6 and 8–14 (each `sops --decrypt` and what it feeds),
`drills/lib/run-drill.sh` (~line 69), `infrastructure/lam/apply-secret.sh`,
`infrastructure/keycloak/persist-operator-credentials.sh`, `infrastructure/keycloak/configure-realm.sh`,
`infrastructure/glpi/configure-glpi.sh`, `infrastructure/observability/configure-grafana-alerting.sh`.
Run `find . -name '*.enc.yaml' -not -path './.git/*'` and list every key in every file in the PR description,
naming where each one is generated after the change.

**Steps:**
1. Add a helper library, `bootstrap/lib/secrets.sh`:
   - `gen_password` → `openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32`.
   - `ensure_secret <namespace> <name> <key>=<value-or-@gen> ...`: if the Secret exists, do nothing
     and keep its existing values. Otherwise create it. Values never appear in argv visible to `ps`
     (use `kubectl create secret generic --from-env-file=<(...)` or stdin), are never echoed, and are never written to a file.
   - `get_secret <namespace> <name> <key>` reads one value for scripts that need it.
   - The script must not enable `set -x`. Add a guard that fails if `xtrace` is on.
2. Replace every `sops --decrypt` in `install.sh` with `ensure_secret`: LDAP bind password, Keycloak admin,
   Keycloak Postgres, OIDC client secrets (Argo CD, Grafana, MinIO), Argo CD OIDC config, MinIO root credentials,
   MariaDB root, GLPI DB, LAM master password. Where two Secrets must hold the *same* value (e.g. the LDAP bind
   password in two namespaces), generate it once and pass it to both.
3. Consumers read from the cluster, not Git: `run-drill.sh`, `lam/apply-secret.sh` and
   `persist-operator-credentials.sh` use `get_secret`.
4. **API tokens.** `configure-glpi.sh` and `configure-grafana-alerting.sh` mint the token against the live service
   (they already know how; check), store it with `ensure_secret`, and are called by `install.sh` as a
   final phase that first waits for those apps to be Healthy (bounded wait with a clear timeout message).
5. **Argo CD repository access:**
   - Public repo (D5): HTTPS `repoURL`, no credential. Change `repoURL` in `bootstrap/root-app*.yaml` and every
     `apps/**` Application that points at this repo, and delete `bootstrap/secrets/argocd-repo-key.enc.yaml`.
   - Private repo: accept `ARGOCD_REPO_TOKEN` (a fine-grained, read-only token) from the environment and create
     the repository Secret from it.
   - Also add `REPO_URL` and `TARGET_REVISION` env overrides (default `main`), which T25 needs to test PR commits.
     The root app and the child Applications must honour `TARGET_REVISION`. Template it in `install.sh` when applying
     the root app, and for children use Argo CD's app-of-apps pattern (the root app passes the revision) or document
     why children stay on `main`.
6. Write `~/.dora-blueprint/credentials.txt` (directory 700, file 600, outside the repo) with one line per UI:
   name, URL (from `ACCESS_HOST` once T03 exists, `localhost` until then), username, and password read back from
   the cluster. `install.sh` prints the file's *path*, never its contents.
7. Update `docs/06-operations.md` ("where credentials come from") and the component pages.

**Tests** (`tests/test_bootstrap_secrets.py`, with `kubectl` stubbed by a fake on `PATH` that records calls):
- `ensure_secret` creates when absent and does nothing when present (second run: zero `create` calls).
- No generated value appears in captured stdout or stderr, or in the recorded argv.
- `grep -rn "sops" --include=*.sh --include=*.py --include=Makefile .` returns nothing outside docs.

**Done when:**
- [ ] All the above, plus the PR description table: every former SOPS key → where it is now generated.
- [ ] `bash -n` passes on every changed script, and shellcheck (pinned) passes on `bootstrap/lib/secrets.sh`.
- [ ] Live checks listed for T17: fresh stand-up with zero manual secret steps; logins work with the values from
  `credentials.txt`; a drill opens a GLPI ticket using the minted token.

**Out of scope:** removing the SOPS files themselves and the age tooling (that's T02c); rotating credentials on a schedule.

---

## T02c · Remove the SOPS plumbing and teach the production pattern

- **Wave / mode:** 1 · offline
- **Depends on:** T02b merged

**Steps:**
1. Delete `.sops.yaml` and every remaining `*.enc.yaml`. Remove `sops` and `age` from `bootstrap/prepare-host.sh`
   and `bootstrap/versions.env`. Remove the age-key checks from `bootstrap/preflight.sh` and their tests in
   `tests/test_host_prep.py`. Remove the secrets entries from `.gitignore` only if nothing else needs them.
2. Amend `BUILD-SPEC.md` P5 to: "No plaintext secrets in Git, and no manual secret creation: every credential
   is generated at stand-up and lives only in the cluster." Add a dated note in §12 explaining the change of
   mind and its reason, in the style of the existing revision notes.
3. New teaching page `docs/guide/secrets-model.md`, added to the MkDocs nav:
   - **What the lab does:** generated, in-cluster, ephemeral; the root CA in-cluster on purpose.
   - **What a regulated firm should do:**
     - an offline root in an HSM, with a key ceremony;
     - an intermediate held in a cloud KMS or HSM-backed issuer (Vault PKI, AWS Private CA, Azure Key Vault,
       Google CAS);
     - application secrets in an external manager (Vault, AWS Secrets Manager, Azure Key Vault,
       Google Secret Manager) synced by External Secrets Operator;
     - rotation, break-glass and dual control.
   - **Where SOPS still fits:** small teams, GitOps-native, with a key-custody plan. Note that this repo
     lost its age key, a real lesson to teach.
   - Map each practice to DORA Art. 9(4)(d), ISO A.8.24/A.5.17, and NIST SC-12/SC-28/IA-5.
4. Gaps register: close G16 with a link. Add a new honest gap: "the root CA is in-cluster and short-lived by
   design; not a production pattern." Update the DORA sheet rows for 9(4)(d) and re-render.
5. Update `docs/components/sops-age.md` (PR #3) to "historical: replaced in T02c". Keep it, because it teaches the trade-off.

**Done when:**
- [ ] No `.enc.yaml` and no `.sops.yaml` remain, and `preflight.sh` doesn't mention age.
- [ ] The host-prep and docs-site tests pass, and `mkdocs build --strict` passes.
- [ ] BUILD-SPEC, the gaps register, the DORA sheet and the CHANGELOG are updated.
