# Track 02: cloud hosting

Goal: any fresh Linux VM (Hetzner, AWS, Azure, GCP) goes from nothing to a running lab with a
documented, repeatable procedure, and the presenter reaches every UI privately from a laptop. Today the
lab only works on the original home server: `192.168.1.106` and the `svc_bob` user are baked into about 55
files.

**Order:** T03 → T04 → T05 → T06 → T08. T06 is independent and can run any time after D4.

Current access map (from `bootstrap/port-forwards/*.service`):

| Service | Namespace / svc | Port |
|---|---|---|
| Argo CD | `argocd/argocd-server` (443) | 9080 |
| Hubble UI | `kube-system/hubble-ui` | 9081 |
| Grafana | `observability/grafana` | 9082 |
| Keycloak | `keycloak/keycloak-keycloakx-http` | 9083 |
| MinIO console | `velero/minio-console` (9001) | 9084 |
| GLPI | `glpi/glpi` | 9085 |
| LAM | `lam/lam` | 9086 |
| Loki gateway (host-only) | `observability/loki-gateway` | 18097 on loopback |

---

## T03 · One configurable access host instead of `192.168.1.106`

- **Wave / mode:** 2 · offline, with a live proof in T17
- **Depends on:** D1. Run it after track 01, because both touch `install.sh`.

**Read first:** the output of `grep -rn 192.168.1.106 --exclude-dir=.git .`. Sort the hits into
(a) functional config, (b) comments, and (c) history (CHANGELOG, BUILD-SPEC narrative, `docs/evidence/samples/`).
Also read `apps/core/grafana.yaml` (root_url, auth_url), `apps/core/minio.yaml` (configUrl, redirectUri),
`infrastructure/cert-manager/certificates/*.yaml` (ipAddresses SANs), `infrastructure/keycloak/configure-realm.sh`
and `configure-minio-oidc.sh` (redirectUris), and `infrastructure/glpi/*.sh` and
`infrastructure/observability/configure-grafana-alerting.sh` (URL defaults).

**Design constraint:** Argo CD renders manifests from Git, so an address used by a *synced* manifest has to
be committed. A runtime environment variable won't reach those manifests.

**Steps:**
1. Add `bootstrap/access.env` with `ACCESS_HOST=` and a comment explaining it. It is the single source of truth.
2. Add `bootstrap/set-access-host.sh <ip-or-hostname>`. It:
   - updates `access.env`;
   - rewrites every functional manifest occurrence of the *current* value to the new one, using an explicit
     file list kept in the script, not a repo-wide sed;
   - validates the input (an IPv4 or a hostname; reject anything else);
   - is idempotent;
   - prints the files it changed and reminds the user to commit and push, so Argo CD syncs the change.
3. Shell scripts (`configure-*.sh` and the like) `source bootstrap/access.env` instead of carrying a literal default.
4. Certificates: put `ACCESS_HOST` in `ipAddresses` if it's an IP, or `dnsNames` if it's a hostname. The script
   must handle both.
5. Rewrite comments that cite the old address to describe the access host generically. Leave history alone.
6. **Pod reachability.** MinIO fetches Keycloak's `configUrl` *from inside a pod*, so the access host must resolve
   and route from pods, not just from the browser. A Tailscale `100.x` IP bound on the VM host is reachable from
   Talos-in-Docker containers through the host's routing. A MagicDNS name usually **won't** resolve inside pods.
   Recommend the IP. If a hostname is used, add a CoreDNS `hosts` entry through GitOps and document it. Test whichever
   you choose in T17.
7. Document the fallback in `docs/guide/demo-vm.md`, but don't make it the default: `ip addr add 192.168.1.106/32 dev lo`
   on the VM, advertised as a Tailscale subnet route, needs zero manifest changes. It is brittle, and it collides
   with any home LAN on 192.168.1.0/24.

**Tests** (`tests/test_access_host.py`):
- No literal `192.168.1.106` outside the history allow-list (CHANGELOG.md, BUILD-SPEC.md, `docs/evidence/samples/`,
  `docs/roadmap/`).
- Running `set-access-host.sh` into a temp copy of the repo with an IP, then a hostname, then the same hostname
  again: the third run changes nothing, and the outputs are valid YAML.
- Every Certificate SAN and OIDC redirect URI uses the value from `access.env`.

**Done when:** all of the above, and the DORA sheet is unchanged (no compliance status changes here).

---

## T04 · Host-agnostic port-forward units

- **Wave / mode:** 2 · offline, with a live proof in T17
- **Depends on:** T03

**Steps:**
1. Replace the eight `.service` files with one template, `bootstrap/port-forwards/port-forward@.service.tmpl`,
   plus a table, `bootstrap/port-forwards/forwards.tsv` (name, namespace, service, local port, remote port,
   `lan`/`loopback`), holding the values in the access map above.
2. `install.sh` renders one unit per row to `/etc/systemd/system/pf-<name>.service`, with:
   - `User=${SUDO_USER:-$USER}`, never a hard-coded user, and `--address ${ACCESS_HOST}` for `lan` rows;
   - Loki staying on loopback;
   - `Restart=always`, `RestartSec=2` and `StartLimitIntervalSec=0` (keep the existing reasoning comments);
   - `KUBECONFIG` pointed at the invoking user's kubeconfig via `Environment=`.
3. Removes units that are no longer listed in the TSV. Idempotent.
4. At the end it prints a URL table (`https://ACCESS_HOST:9082` and so on) and the path of `~/.dora-blueprint/credentials.txt`.
5. Update `bootstrap/port-forwards/README.md`: what this is, why systemd, and why not an Ingress (that's the
   unscheduled "bastion/Ingress" roadmap item; link it).

**Tests:** render into a temp dir with a fake `systemctl`. Assert one unit per TSV row, no `svc_bob` and no
literal IP in any template, and that Loki has no `--address`. Run `systemd-analyze verify` on the rendered units
when it's available (skip cleanly otherwise).

**Done when:** tests pass, and `grep -rn "svc_bob" bootstrap/` is empty.

---

## T05 · Tailscale in host prep

- **Wave / mode:** 2 · offline
- **Depends on:** D3, PR #4 merged

**Read first:** `bootstrap/prepare-host.sh`, `bootstrap/preflight.sh`, `bootstrap/versions.env`,
`tests/test_host_prep.py`, `docs/guide/demo-vm.md`, and Tailscale's Linux install documentation.

**Steps:**
1. `prepare-host.sh --tailscale`:
   - adds Tailscale's signed apt repository (keyring pinned by fingerprint) and installs a version pinned in
     `versions.env`;
   - runs `tailscale up --authkey "$TS_AUTHKEY" --hostname "${TS_HOSTNAME:-dora-demo}" --ssh=false`;
   - reads `TS_AUTHKEY` from the environment only, fails clearly if it's missing, and never logs or writes it.
2. Print the VM's Tailscale IPv4 and suggest `bash bootstrap/set-access-host.sh <that IP>`.
3. `preflight.sh` adds a WARN check, "ACCESS_HOST from access.env is assigned to a local interface", and a FAIL
   check if `ACCESS_HOST` is empty.
4. Docs: a laptop-side section in `demo-vm.md` covering installing Tailscale, joining the same tailnet, opening
   `https://ACCESS_HOST:9082`, importing the root CA from `make ca-export` (T02a) or clicking through, and what to
   do on venue Wi-Fi that blocks UDP (Tailscale DERP relays over 443; test it beforehand).

**Tests:** extend `tests/test_host_prep.py` with a stubbed `tailscale` and `apt-get`. Cover the missing-key failure,
idempotent re-runs, and that the auth key never appears in captured output.

**Done when:** tests pass, and the docs cover both the VM and the laptop side.

---

## T06 · Fix the `canary-writer` image pull

- **Wave / mode:** 2 · offline
- **Depends on:** D4

**Background:** `canary/deployment.yaml` pins `ghcr.io/utility-soc/canary-writer@sha256:a59f3c…`. The package is
private and the cluster has no pull credential, so the last CHANGELOG entry shows `ImagePullBackOff`. Weekly
rebuilds produce new digests.

**Steps, if the package is public (recommended):**
1. Document the GHCR visibility setting in `docs/guide/demo-vm.md` and `docs/components/apko-wolfi.md`.
2. Add a final job to `.github/workflows/build-images.yaml` that, with no credentials, pulls the new digest
   (`docker logout ghcr.io && docker pull <digest>`). It proves the package is public, and it fails the build if not.
3. Check that the pinned digest in `canary/deployment.yaml` still exists and is signed:
   `cosign verify` with the exact identity used in `infrastructure/kyverno/policies/verify-image-signatures.yaml`.
   If it's gone or unsigned, update it to the latest signed digest from the workflow's run output. Grep
   `drills/templates/` for other references.
4. Optional: a small `scripts/bump-canary-digest.sh` that takes a digest, verifies the signature and attestation, and
   rewrites every reference.

**Steps, if the package stays private:** create a `dockerconfigjson` Secret from a read-only `read:packages`
token passed as `GHCR_PULL_TOKEN` at stand-up (never committed), in the `canary` and `argo-workflows` namespaces.
Add `imagePullSecrets` everywhere the image is used. Note the extra credential in `secrets-model.md`.

**Tests:** every reference to `ghcr.io/utility-soc/canary-writer` uses the same digest, a test asserts no tags,
and the workflow YAML parses.

**Done when:** an anonymous pull of the pinned digest succeeds (paste the output in the PR), or the private path
is wired and tested.

---

## T08 · One-command VM provisioning (cloud-init)

- **Wave / mode:** 2 · offline
- **Depends on:** D2, T05

**Files:** new `bootstrap/cloud/cloud-init.yaml`, `bootstrap/cloud/README.md`, `bootstrap/cloud/hetzner.sh`, and optionally
`aws.sh`, `azure.sh`, `gcp.sh`.

**Steps:**
1. Generic `cloud-init.yaml`:
   - creates user `demo` with sudo and your SSH public key (templated; never a private key);
   - sets up `unattended-upgrades` for security updates with **`Automatic-Reboot "false"`** (a reboot takes about
     28 minutes to settle, per the runbook);
   - sets the timezone to UTC, NTP via chrony, and a 4 GB swapfile;
   - clones the repo over HTTPS at a pinned ref (an argument);
   - runs `prepare-host.sh` (without `--tailscale`; the auth key is supplied interactively afterwards);
   - installs Claude Code if D7 is chosen (its official install method, version pinned);
   - writes a `/etc/motd` listing the next steps.
2. **Cost guard:** a systemd timer that runs every 30 minutes and powers the VM off when there's been no SSH session
   and no `make drill` process for N hours (default 4, configurable). Document that some providers keep billing a
   powered-off VM (Hetzner does), so it's a guard, not a replacement for destroying the VM.
3. `hetzner.sh create|destroy|status`, wrapping `hcloud` (pinned version):
   - CCX33 in a chosen EU location, Ubuntu 24.04, cloud-init attached, firewall allowing **SSH only**
     (Tailscale needs no inbound ports);
   - prints the IP and the hourly price;
   - `destroy` asks for confirmation unless `--yes`.
4. The README covers create → SSH in → `TS_AUTHKEY=… bash bootstrap/prepare-host.sh --tailscale` →
   `set-access-host.sh` → commit and push → `preflight.sh` → `make lab-full` → `port-forwards/install.sh` → destroy,
   with timings and cost per hour. Never put the Tailscale key or any token in user-data: user-data is readable from
   the instance metadata service.

**Tests:** `cloud-init schema --config-file bootstrap/cloud/cloud-init.yaml` if available (pip install the pinned
`cloud-init` in CI; it works on Linux runners); `bash -n` and shellcheck on the scripts; a test that
`cloud-init.yaml` contains no key-like material.

**Done when:** the schema is valid and the README is complete enough that a stranger could follow it. The live run
happens in T17.
