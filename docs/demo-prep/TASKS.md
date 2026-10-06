# Demo-readiness backlog

Written 2026-10-06 from a full review of `main` plus the four open PRs. The goal: a live
demo of this lab, hosted on a cloud VM, for financial-sector audiences in Dublin. The
companion talk track is [`DEMO-SCRIPT.md`](DEMO-SCRIPT.md).

Each task below is sized for one agent session (Sonnet) and is self-contained. Hand over one
task at a time, using the prompt template at the bottom of this file.

---

## 1. Where the project stands

**Built and on `main`:** Talos + Cilium + Argo CD GitOps platform. Five measured drill scenarios
(ns-restore, node-kill, pvc-corruption-restore, network-partition, credential-compromise).
DORA Art. 18 classification as code, Art. 19 / NIS2 Art. 23 clocks, GLPI tickets, Tetragon
detection, Trivy + CISA KEV, signed images with SBOM attestation, generated Register of
Information, a hash-chained evidence store with a keyless-signed chain head, OSCAL export, and
NIST 800-53 / ATT&CK crosswalks. `make evidence` and `make evidence-verify` run cleanly offline
today.

**Built but not merged.** All four PRs are open:

| PR | Branch | What it adds | Why the demo needs it |
|---|---|---|---|
| [#1](https://github.com/Utility-SOC/dora-blueprint/pull/1) | `chore/rekey-secrets-lowmem-bootstrap` | All SOPS secrets re-encrypted to a **new** age key; `MEMORY_*` / `WORKERS=0` knobs | Its `install.sh` memory knobs. Its re-encrypted secrets get deleted by T02, so it is no longer a blocker |
| [#2](https://github.com/Utility-SOC/dora-blueprint/pull/2) | `test/offline-test-suite` | 345 offline tests, CI, a DORA clock fix for delayed classification | Credibility, and a safety net for every task below |
| [#3](https://github.com/Utility-SOC/dora-blueprint/pull/3) | `docs/site-and-guides` (stacked on #2) | MkDocs site, executive guide, article-level compliance mapping, **gaps register** (G1–G24) | The public showcase and the honesty story |
| [#4](https://github.com/Utility-SOC/dora-blueprint/pull/4) | `demo/host-prep` (stacked on #3) | `prepare-host.sh`, `preflight.sh`, `versions.env`, `docs/guide/demo-vm.md` | The cloud-VM bring-up path |

I test-merged #1 into #4 locally. There are no conflicts.

**Not ready for a cloud demo.** In order of severity:

1. **Committed secrets are a liability for a demo.** Seven SOPS files (`find . -name '*.enc.yaml'`)
   tie every stand-up to one person's age key. That key has been lost once already (G16), and PR #1
   is the cleanup. The public CA certs in `infrastructure/cert-manager/ca-certs/*.crt` and
   `drills/templates/platform-ca-configmap.yaml` still carry the **July 29** certificates even though
   PR #1 re-issued the CA. That is exactly the drift this model invites. **Decision (owner,
   2026-10-06): every stand-up generates its own PKI and credentials. Nothing secret is committed.**
   See T02a–T02c.
2. **The cluster has not booted since the secrets re-key** (gap G20). Every evidence sample predates
   the current secrets. Nothing live has been proven on the current code.
3. **`192.168.1.106` (a home-LAN address) is hard-coded in about 55 files.** That includes OIDC
   redirect URIs, certificate SANs, Grafana `root_url`, MinIO's OIDC config, and the systemd
   port-forward units (which also hard-code the `svc_bob` user). None of it works on a cloud VM
   as committed.
4. **The `canary-writer` image was stuck in `ImagePullBackOff`.** The GHCR package is private and
   the cluster has no pull credential.
5. **Placeholder GLPI and Grafana API tokens** (G19). The incident-ticket step will fail until
   these are real.
6. **The headline claim isn't fully true yet.** The README thesis says "measures them, *on a
   schedule*", but no drill is scheduled (G4). Drill verdicts also ignore the RTO/RPO targets (G3),
   and one committed sample has a negative RPO (G15).
7. **Showcase gaps:** no screenshots or asciinema (Phase 15). The README "Observability" section
   still claims an Elastic/Fleet profile that doesn't exist. `docs/01-risk-assessment.md` and
   `docs/02-statement-of-applicability.md` are linked but missing (G14).

---

## 2. Decisions only you can make

Settle these before handing out tasks. My recommendation comes first in each row.

| # | Decision | Recommendation | Unblocks |
|---|---|---|---|
| D1 | Merge PRs #1–#4? | **Yes.** Merge #1 first (its `MEMORY_*`/`WORKERS=0` knobs are worth keeping; T02 then deletes its re-encrypted files), then #2 → #3 → #4. After each merge, update the next PR's base to `main` | Everything |
| D2 | Cloud provider / region | **Rehearse on Hetzner CCX33** (dedicated, ~€0.22/h, EU). For the talk itself, consider **AWS eu-west-1 or Azure North Europe, both in Dublin**: "this demo is running in Dublin right now" lands well with this audience. Destroy the VM between sessions | T08, Phase D |
| D3 | How you reach the UIs | **Tailscale** on the VM and on your laptop: private, no public ports, works on venue Wi-Fi. Avoid exposing Keycloak/Argo/GLPI to the internet | T03–T05 |
| D4 | GHCR `canary-writer` visibility | **Make the package public.** It is signed and SBOM-attested, so public is the honest supply-chain story. The alternative is a pull secret generated at stand-up from a token in an env var (T06 handles either) |
| ~~D6~~ | ~~Age key on a rented VM~~ | **Resolved by your call:** secrets are generated per stand-up (T02a–c), so there is no key to carry | — |
| D5 | Make the repo public? | **Yes, after T23 (audit).** Hiring managers need to click a link, and Pages on a private repo needs a paid plan. It also means Argo CD can read the repo over HTTPS with **no credential at all**. That removes the last committed secret (the deploy key) | T02b, T22 |
| D7 | Who operates the VM | **Install Claude Code on the VM itself.** Then Sonnet can run the "live" tasks there with real `kubectl` access. Your laptop only needs SSH and a browser | Phase D |

---

## 3. Critical path

```
D1 merge PRs ──► T02a PKI ─► T02b credentials ─► T02c drop SOPS
                     T03 access host ──► T04 port-forwards ──► T08 VM provisioning
                     T06 image pull ─┘                               │
T07 CI pinning  (any time)                                                         ▼
T09 verdict/targets ─┐                                             T17 bring-up (live)
T10 clocks 72h/1mo  ─┼─► merged before bring-up ──────────────────► T19 fresh evidence
T11 scheduled drills ┘                                                            ├─► T20 screenshots/asciinema
T12 negative-RPO bug ─────────────────────────────────────────────────────────────┘
T15 risk assessment + SoA, T16 README ─► T23 public audit ─► T22 Pages site
                                                              T26 rehearsal ×2 ─► demo
```

**Offline** = Sonnet can finish it in a normal cloud session with no cluster.
**Live** = needs the running VM (Claude Code on the VM, or you running the commands).

Rough effort: Phase B+C offline ≈ 12–16 Sonnet sessions; Phase D live ≈ 2–4 days of
bring-up and debugging, judging by the CHANGELOG's history of "caught live" fixes.

---

## 3½. Roadmap by facet: what to hand Sonnet, in what order

The project has ten facets. Each row is a track. Tasks within a track run **in order**. Tracks in
the same wave touch different files and can run **in parallel sessions**.

| Wave | Track | Tasks (in order) | Touches | Parallel-safe with |
|---|---|---|---|---|
| 0 | **You:** merge and decide | D1–D5, D7 | GitHub settings | — |
| 1 | Secrets and PKI | T02a → T02b → T02c | `bootstrap/install.sh`, `infrastructure/cert-manager/`, scripts | CI pinning, Claims |
| 1 | CI pinning | T07 | `.github/workflows/` | everything in wave 1 |
| 1 | Claims made true | T09 → T10 → T12 → T11 | `drills/` | Secrets, CI |
| 1 | Documents | T15 → T16 | `docs/`, README | everything in wave 1 |
| 2 | Cloud hosting | T03 → T04 → T05 → T06 → T08 | manifests (address), `bootstrap/` | Documents. **Not** Secrets; both edit `install.sh`, so run after wave 1 |
| 2 | Optional polish | T13, T14, T24 | Grafana, Keycloak scripts, docs site | each other |
| 3 | **Live** bring-up and evidence | T17 → T18 → T19 → T20 → T21 | the VM; fixes go back to Git | nothing; one operator |
| 4 | Showcase | T23 → T22 → T26 | repo settings, docs site | — |
| 5 | Alternatives and cloud | F01a, F01b, F01c, F01d, then F02 | `docs/components/`, `docs/architecture/` | all four F01s with each other |
| 5 | ISO 27001 programme | F03 → F04 | `docs/isms/` | Alternatives |
| 6 | FedRAMP 20x / IL5 | F05 → F06 → F07 | `docs/compliance/`, `docs/evidence/` | Baselines |
| 6 | Hardening baselines | F10a → (F10b, F10c, F10d, F10e in parallel) → F10f → F10g | `baselines/`, CI | FedRAMP |
| 7 | Live hardening + capstone | F08 → F09 | the VM, `docs/guide/` | — |

**Waves 0–4 are the demo** (about 20–25 Sonnet sessions plus a few days of live bring-up).
**Waves 5–7 are the teaching build-out** (about 25–30 sessions). Each task ID is one session. If a
session runs out of context, give it the same task ID again with "continue from the open PR."

**Where to spend more than Sonnet.** These tasks are cheap to get subtly wrong. Have Sonnet do the work,
then have a stronger model *review the PR*, not redo it:
- T02a/T02b: credential handling and PKI design.
- T10, F06, F07: reading regulation and FedRAMP/DoD text precisely.
- F05: classification judgements across about 400 controls.

**Keep every session on rails** with the prompt template in §5: one task ID, its own branch, tests
before push, CHANGELOG entry, a PR whose description ticks off the task's "Done when". Merge each PR
before starting a task that depends on it. Stacked, unmerged branches are how PRs #1–#4 ended up
waiting.

---

## 4. Tasks

Every task's acceptance criteria include: `pytest` passes (once #2 is merged), `make evidence-verify`
passes, CHANGELOG.md gets an entry, and the work follows `BUILD-SPEC.md` §1 principles P1–P8.

### Phase A½ — ephemeral secrets: every stand-up rolls its own (all offline)

**Owner decision, 2026-10-06:** this is a demo and a teaching tool, so no secret material lives in
Git. Each `make lab-*` generates a fresh CA chain and fresh credentials. Destroying the VM destroys
them. This replaces the SOPS/age model and removes gaps G16 and the stale-CA problem outright.
The production pattern still gets taught in docs (T02c), just not run.

Do these three in order, each as its own PR, after D1.

#### T02a · Generate the PKI in-cluster with cert-manager (no committed CA)
- **Why:** the committed CA certs drifted from the re-issued key (§1 item 1), and an offline root
  kept on someone's disk is what got lost.
- **Files:** `infrastructure/cert-manager/issuer/`, `infrastructure/cert-manager/ca-certs/` (delete),
  `infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml` (delete), `apps/core/cert-manager-issuer.yaml`,
  `drills/templates/platform-ca-configmap.yaml` (replace), the three drill templates that mount it,
  `bootstrap/install.sh` step 7 (delete), `docs/runbooks/pki-root-ca-issuance.md`.
- **Design (standard cert-manager CA bootstrap, all GitOps):**
  1. `ClusterIssuer selfsigned-bootstrap` (`selfSigned: {}`).
  2. `Certificate platform-root-ca` in `cert-manager`: `isCA: true`, ECDSA P-256 or P-384, 10-year
     duration, issued by `selfsigned-bootstrap`. Subject keeps `C=IE, O=Resilience Lab`.
  3. `ClusterIssuer platform-root` (`ca.secretName: platform-root-ca`).
  4. `Certificate intermediate-ca`: `isCA: true`, 5-year duration, issued by `platform-root`, written to
     secret `intermediate-ca`. That is the name the existing `ClusterIssuer platform-ca` already uses,
     so every leaf `Certificate` keeps working unchanged.
  5. Order with Argo CD sync waves. A leaf cert must not race the intermediate.
  6. Distribute the root to workloads with **trust-manager** (pinned chart, its own Argo app,
     AppProject updated, Cilium egress policy if needed). A `Bundle` replaces the hand-pasted
     `platform-ca-configmap.yaml`. Point the drill templates' volume at the bundle's ConfigMap.
  7. `make ca-export` (or an `install.sh` final step) writes the root's public cert to
     `~/dora-blueprint-root-ca.crt` on the VM, so the presenter can import it into the laptop browser
     once per stand-up. Document click-through as the alternative.
- **Teaching note to write into the runbook:** in production the root stays offline (HSM or air-gapped)
  and only the intermediate lives in-cluster. Here the root is in-cluster *on purpose* so any
  stranger can stand the lab up. Add that to `docs/04-limitations.md` and update the PKI rows of
  `docs/03-control-matrix.md`. The old `pki-chain-verification` sample stays as history.
- **Done when:** rendered manifests validate offline; a test asserts no `BEGIN CERTIFICATE` or
  `BEGIN .*PRIVATE KEY` remains anywhere outside `docs/evidence/samples/`; and `issuerRef` chains
  resolve (a test can walk them in the YAML). Live proof (leaf certs Ready, `openssl s_client`
  shows the chain) happens in T17.

#### T02b · Generate every credential at bootstrap; nothing read from SOPS
- **Depends on:** T02a.
- **Files:** `bootstrap/install.sh` (steps 6, 8–14), `drills/lib/run-drill.sh` (line ~69),
  `infrastructure/lam/apply-secret.sh`, `infrastructure/keycloak/persist-operator-credentials.sh`,
  `infrastructure/glpi/configure-glpi.sh`, `infrastructure/observability/configure-grafana-alerting.sh`,
  `infrastructure/keycloak/configure-realm.sh`.
- **Steps:**
  1. Add a helper, `ensure_secret <ns> <name> <key>=<generator>...`, to `install.sh`. It creates
     the Kubernetes Secret only **if absent**, with values from `openssl rand -base64 32 | tr -d '/+='`.
     Re-runs are idempotent and keep existing values. No temp files on disk, and no values echoed
     or passed via `set -x`.
  2. Replace every `sops --decrypt` in `install.sh` with `ensure_secret`: LDAP bind, Keycloak admin
     and Postgres, OIDC client secrets, Argo CD OIDC, MinIO root, GLPI/MariaDB, LAM master password.
  3. **Consumers read from the cluster, not Git.** `run-drill.sh`, `apply-secret.sh`, and
     `persist-operator-credentials.sh` use `kubectl get secret … -o jsonpath | base64 -d`.
  4. **API tokens** (GLPI, Grafana) are minted by their configure scripts against the live service
     after sync, then stored as Secrets. They are not committed. That closes G19 by construction.
  5. **Argo CD repo access:** if the repo is public (D5), use HTTPS with no credential and drop
     `bootstrap/secrets/argocd-repo-key.enc.yaml`. If private, accept a deploy key or fine-grained
     token from an env var (`ARGOCD_REPO_TOKEN`) at install time. Never write it to disk.
  6. Final step: write `~/.dora-blueprint/credentials.txt` (mode 600, **outside the repo**) listing each
     UI's URL, username, and generated password, so the presenter can log in. Print its path, not its
     contents.
- **Done when:** `grep -rn "sops" --include=*.sh --include=*.py .` returns nothing outside docs.
  A test runs `install.sh`'s secret helper against a stubbed `kubectl` and checks it is idempotent
  and leaks nothing to stdout. Live proof in T17.

#### T02c · Remove the SOPS plumbing and teach the production pattern instead
- **Depends on:** T02b.
- **Steps:** delete `.sops.yaml` and all `*.enc.yaml`. Remove `sops`/`age` from
  `bootstrap/prepare-host.sh`, `versions.env`, `preflight.sh` (and its age-key checks), and their tests.
  Update `.gitignore`. Amend `BUILD-SPEC.md` P5 to "No plaintext secrets in Git, and no manual secret
  creation: every credential is generated at stand-up and lives only in the cluster." Record the
  change of mind with its reason, as §12 already does for other revisions.
- **Write `docs/guide/secrets-model.md`**, a teaching page: what this demo does (ephemeral, generated,
  in-cluster root) versus what a regulated entity should do (offline root/HSM, an external secrets
  manager via External Secrets Operator or Vault, rotation, and break-glass). Map each to DORA Art. 9(4)(d)
  and ISO A.8.24. Add it to the MkDocs nav. Close G16 in `gaps.md` and add a new honest gap: "root CA is
  in-cluster and short-lived by design; not a production pattern."
- **Done when:** no `.enc.yaml` remains, the docs-site and host-prep tests pass, and `preflight.sh`
  no longer mentions age.

### Phase B — make it cloud-hostable (all offline)

#### T03 · Replace the hard-coded `192.168.1.106` with one configurable access host
- **Why:** §1 item 3. Today the lab only works on the original home server.
- **Files:** `grep -rln 192.168.1.106 --exclude-dir=.git .` (about 55 hits). Code that needs changing:
  `apps/core/grafana.yaml`, `apps/core/minio.yaml`, `infrastructure/cert-manager/certificates/*.yaml`,
  `infrastructure/keycloak/*.sh`, `infrastructure/glpi/*.sh`, `infrastructure/observability/configure-grafana-alerting.sh`,
  `infrastructure/cilium/**` (comments), `bootstrap/port-forwards/*.service`.
- **Design constraint:** Argo CD renders manifests from Git, so the address must be committed.
  A runtime env var won't reach it. Recommended shape:
  1. `bootstrap/access.env` holds `ACCESS_HOST=` (one IP or hostname) as the single source of truth.
  2. `bootstrap/set-access-host.sh <host>` rewrites every *manifest/script* occurrence. Shell
     scripts should read `access.env` instead of a literal default. Running it twice with the
     same value changes nothing.
  3. Leave historical mentions in `CHANGELOG.md` and evidence samples alone. They are history.
  4. Add a test: no literal `192.168.1.106` remains outside CHANGELOG / `docs/evidence/samples/` / BUILD-SPEC.
- **Watch out:** MinIO fetches Keycloak's `configUrl` **server-side, from inside a pod**. The access
  host must be reachable from pods as well as from the browser. A Tailscale `100.x` IP on the VM
  host is reachable from the Talos-in-Docker containers. A MagicDNS hostname may **not** resolve
  inside pods. Prefer the IP, or add a CoreDNS `hosts` entry, and document which you chose.
- **Fallback (document it, don't make it the default):** on the VM, `ip addr add 192.168.1.106/32 dev lo`
  and advertise it as a Tailscale subnet route. This needs zero manifest changes, but it's brittle
  and looks odd to a reviewer.
- **Done when:** a fresh grep is clean, the script is idempotent, the test passes, and `docs/guide/demo-vm.md` explains it.

#### T04 · Make the port-forward units host-agnostic
- **Depends on:** T03.
- **Files:** `bootstrap/port-forwards/*`.
- **Steps:** turn the eight `.service` files into one template, rendered by `install.sh` from
  `access.env` plus the invoking user (`${SUDO_USER:-$USER}`) instead of `svc_bob`. Keep `Restart=always`
  and `StartLimitIntervalSec=0`. Keep Loki loopback-only. Have `install.sh` print the URL table at the
  end (Grafana `https://HOST:9082`, Argo CD `:9080`, Keycloak `:9083`, MinIO `:9084`, GLPI `:9085`,
  Hubble, LAM). Check the real ports in the units; don't trust this list.
- **Done when:** rendering into a temp dir produces valid units (unit test with `systemd-analyze verify`
  if available, else a string test). `svc_bob` and `192.168.1.106` appear nowhere in `bootstrap/port-forwards/`.

#### T05 · Add Tailscale to host prep
- **Depends on:** D3, and PR #4 merged.
- **Files:** `bootstrap/prepare-host.sh`, `bootstrap/preflight.sh`, `bootstrap/versions.env`, `docs/guide/demo-vm.md`.
- **Steps:** optional `--tailscale` flag that installs a **pinned** Tailscale version from its signed
  apt repo and runs `tailscale up --authkey "$TS_AUTHKEY" --hostname dora-demo` (the auth key comes from an env
  var, never written to disk or the repo). `preflight.sh` gains a WARN check: is `ACCESS_HOST`
  assigned to a local interface? Extend `tests/test_host_prep.py` with stubbed commands.
- **Done when:** tests pass, and the runbook shows laptop-side steps (install Tailscale, open `https://ACCESS_HOST:9082`,
  trust the lab root CA or click through).

#### T06 · Fix `canary-writer` image pull
- **Depends on:** D4.
- **If public:** document the GHCR visibility setting in `docs/guide/demo-vm.md`. Add a CI step
  to `build-images.yaml` that anonymously pulls the new digest (proves it's public), then **verify** the
  digest pinned in `canary/deployment.yaml` still exists. Update it to the latest signed digest if needed.
- **If private:** a `dockerconfigjson` built at stand-up from a read-only `read:packages` token passed in an
  env var (never committed), created by `install.sh` in the `canary` and `argo-workflows` namespaces, plus `imagePullSecrets` wherever the
  image is used. Grep `drills/templates` too.
- **Done when:** an anonymous `docker pull` or `crane digest` of the pinned digest succeeds (public), or
  the secret path is wired and tested (private).

#### T07 · Pin CI tooling by version and SHA (G18)
- **Files:** `.github/workflows/*.yaml`.
- **Steps:** replace `go install chainguard.dev/apko@latest` with a pinned release (prefer the
  release binary plus a checksum over `go install`). Pin every `uses:` to a full commit SHA with a
  `# vX.Y.Z` comment. Pin `actions/setup-go` `go-version`. Add a test that no workflow contains
  `@latest`, `: stable`, or a tag-only `uses:`.
- **Done when:** the test passes and workflows still parse. Mark G18 fixed in `docs/compliance/gaps.md`.

#### T08 · One-command VM provisioning (cloud-init)
- **Depends on:** D2, T05.
- **Files:** new `bootstrap/cloud/` with `cloud-init.yaml` and `README.md`. Optional: `hetzner.sh`
  and `aws.sh` wrappers around `hcloud` / `aws ec2 run-instances`.
- **Steps:** the user-data creates a non-root user, installs the SSH key, and runs `prepare-host.sh --tailscale`.
  It clones the repo (deploy key or HTTPS), sets up `unattended-upgrades` with **auto-reboot off**
  (the runbook says a reboot takes about 28 minutes to settle), and a cost guard: a systemd timer that
  powers off after N idle hours. **Never** put the Tailscale auth key or any token in user-data. Print the
  next manual steps (`tailscale up` with your auth key → `preflight.sh` → `make lab-full`).
- **Done when:** `cloud-init schema --config-file` validates. A dry-run doc shows the exact
  create/destroy commands and hourly cost.

### Phase C — make the claims true (offline code, verified live in Phase D)

#### T09 · Drill verdict must honour RTO/RPO targets (G3)
- **Files:** `drills/templates/*-workflowtemplate.yaml` (verdict computation), `drills/lib/enrich.py`
  or a new `drills/lib/verdict.py`, `drills/schema/drill-record.schema.json`, tests.
- **Steps:** verdict = `fail` if `integrity_check != pass`, OR `measured_rto_seconds > target_rto_seconds`,
  OR RPO exceeds target. Add `verdict_reasons: [..]`. Do it host-side in Python (testable), not only in
  shell inside the template. Keep the template's own verdict as `recovery_verdict` if the split helps.
  Tests cover each boundary (equal to target = pass).
- **Done when:** tests pass, the schema validates old samples (new field optional), and G3 is marked fixed-pending-live.

#### T10 · Intermediate and final reporting deadlines (G12)
- **Files:** `drills/lib/clocks.py`, the schema, `drills/lib/open-incident.py`, tests.
- **Steps:** look up the actual time limits in Commission Delegated Regulation (EU) 2025/301 (DORA
  Art. 20 RTS on content and time limits) and NIS2 Art. 23(4) **from primary sources**. Cite article
  and paragraph in docstrings. Add `t_intermediate_due_dora`, `t_final_due_dora`,
  `t_notification_due_nis2`, `t_final_due_nis2`. Where a deadline runs from a prior *submission*
  (not detection), compute it assuming on-time submission and say so in the field description.
  The GLPI ticket body gets a deadline table showing both regimes side by side.
- **Done when:** tests pin each deadline against hand-computed fixtures, including the delayed-classification
  case PR #2 fixed. Mark G12 fixed.

#### T11 · Schedule the drills (G4), making "on a schedule" true
- **Files:** new `drills/templates/*-cronworkflow.yaml`, `drills/templates/kustomization.yaml` or the
  app that syncs them, `docs/06-operations.md`, README.
- **Steps:** one `CronWorkflow` per low-blast-radius scenario (ns-restore, pvc-corruption-restore,
  network-partition, credential-compromise; **not** node-kill by default). Stagger schedules, use
  `concurrencyPolicy: Forbid`, and keep history limits small. The record must reach Loki with no
  laptop involved. Today the classify/clocks/GLPI steps run host-side in `run-drill.sh`, so either move
  that enrichment into a final workflow step (preferred; same Python, run in a pinned python image)
  or document that scheduled runs produce raw records only. Add a Grafana "last successful drill
  per scenario" panel and an alert when one is older than 2× its interval. That alert is the
  build spec's own "a drill that fails to emit a record is itself a control failure."
- **Done when:** manifests validate offline (kubeconform or a schema test), and the alert rule exists.
  The live proof is in T19.

#### T12 · Find the negative-RPO bug (G15)
- **Files:** `docs/guide/reading-the-evidence.md` (has a hypothesis), `drills/templates/ns-restore-workflowtemplate.yaml`,
  `pvc-corruption-restore-workflowtemplate.yaml`, `canary/writer.py`, `canary/verify.py`.
- **Steps:** read how `max(counter)` is captured before the fault and after restore. Find the race
  (e.g. the pre-fault read lagging the backup, or reading a different replica/PVC). Fix it so
  `records_lost >= 0` by construction. Add a guard: a negative value marks the record
  `integrity_check: fail` with a reason rather than emitting nonsense. Do **not** edit or delete the
  historical sample. That would break the hash chain and be dishonest. Annotate it in
  `reading-the-evidence.md` instead.
- **Done when:** a unit test reproduces the race with fake counters and the fix passes. Live
  confirmation in T19.

#### T13 · Alert notifications (G8) — *optional, nice on stage*
- Add a Grafana contact point to a webhook (ntfy.sh topic or a Teams/Slack incoming webhook, with the URL
  passed in at stand-up like every other credential) for the two detection rules. On stage, your phone buzzes when the credential-compromise
  drill fires. Mark G8 fixed.

#### T14 · MFA for operators (G7) — *optional, strong signal for finance audiences*
- `infrastructure/keycloak/configure-realm.sh`: require OTP (TOTP) for the platform realm's
  operator group via a conditional authentication flow. Keep a documented break-glass path. Update
  `docs/03-control-matrix.md` (DORA Art. 9(4)(d)) and mark G7 fixed-pending-live.

#### T15 · Write the risk assessment and Statement of Applicability (G14)
- **Files:** new `docs/01-risk-assessment.md` and `docs/02-statement-of-applicability.md`. Both are
  already linked from `00-scope.md` and `04-limitations.md`.
- **Steps:** a risk register for the notional payment institution "Meridian Pay" from `00-scope.md`:
  about 12–15 ICT risks, each with likelihood × impact, the controls in this repo that treat it (link
  files and evidence), residual risk, and owner role (the three-operator model). Every "treated by"
  link must resolve (P1). The SoA lists all 93 ISO 27001:2022 Annex A controls with
  applicable / not-applicable, a justification, and a pointer to implementation or to `04-limitations.md`.
  Use control *titles* only (the standard's text is copyrighted). Add both to the MkDocs nav.
- **Done when:** the docs-site test passes, links resolve, and G14 is marked fixed.

#### T16 · README: demo-first front page and stale claims
- **Steps:** remove the false "Observability … `full` profile adds Elastic/Fleet" section (Tetragon +
  Trivy is the real full tier). Restructure the top of the README: a three-sentence pitch, a
  screenshot/GIF slot (filled in T20), "watch a drill" (asciinema), the tier table, a link to the docs
  site, then status. Move the long phase table and roadmap prose to `docs/roadmap.md`.
  Keep every claim backed by a file (P1).
- **Done when:** the README fits in about two screens above "Status", and a test greps for `Elastic/Fleet` in
  the README and fails if found.

### Phase D — bring-up and fresh evidence (live, on the VM)

#### T17 · First cloud bring-up
- **Depends on:** D1, T02a–c, T03–T06, T08, and ideally T09–T12 merged.
- **Steps:** provision, `preflight.sh` (0 failed), `make lab-full`, and time each of the 14
  steps. Run `bootstrap/port-forwards/install.sh`. Open every UI from the laptop over Tailscale. Log in
  through Keycloak to Argo CD and Grafana. **Expect breakage.** For each failure: root-cause it, fix it
  in Git, push, and add a CHANGELOG "caught live" entry, the same discipline as every earlier phase.
  Don't hot-patch the cluster.
- **Done when:** all Argo CD apps are Synced/Healthy, the canary is writing, and the bring-up time is recorded in
  `docs/guide/demo-vm.md`. Repeat from a **fresh** VM once more (BUILD-SPEC Phase 1: "works twice in a row from clean").

#### T18 · Prove the generated API tokens work end to end (G19)
- After T02b, the GLPI and Grafana tokens are minted on every stand-up. Confirm on the live cluster
  that `install.sh` mints them unattended, that a drill opens a real GLPI ticket with them, and that
  the Grafana alerting configuration applies. Mark G19 fixed with a link to the ticket's evidence sample.

#### T19 · Fresh evidence on current keys (G20, G15, G4 live proof)
- Run all five drills. Run `ns-restore` 3× and note the RTO spread. Let the CronWorkflows (T11) fire at
  least once. Copy the new samples into `docs/evidence/samples/`, tag them in `manifest.yaml`, run
  `make evidence`, and commit (the chain grows; nothing is rewritten). Confirm no negative RPO and that
  verdicts reflect targets. Close G15/G20 with links to the new samples.

#### T20 · Screenshots and recordings (Phase 15)
- Capture: Argo CD app tree, the Grafana RTO/RPO trend dashboard, the vulnerability/KEV dashboard,
  the detection alert firing, a GLPI ticket showing both DORA and NIS2 deadlines, the Hubble flow map
  with a denied flow, and a Kyverno admission denial in the terminal. Record `asciinema rec` of
  `make drill SCENARIO=ns-restore` (sped up in post if needed) and convert it to GIF/SVG with `agg`.
  Store everything under `docs/assets/` with a README noting the date and git SHA. Embed it in the README
  and the docs site. Redact nothing sensitive, because nothing sensitive should be on screen. Check first.

#### T21 · Snapshot, teardown, cost guard
- A `make demo-down` target (or script) that exports the fresh evidence, then destroys the VM via
  the provider CLI. Document the snapshot-and-restore option if the provider makes snapshots cheap.
  Record the real hourly cost.

### Phase E — showcase and narrative

#### T22 · Publish the docs site
- **Depends on:** D5, T23. PR #3 already has an optional Pages deploy job: enable it, set
  `site_url`, and check the strict build. Add a landing page "For hiring managers: the 5-minute tour"
  linking the executive summary, one drill record explained line by line, the control matrix, and the
  gaps register.

#### T23 · Public-readiness audit
- Run the GitHub secret scanner and `gitleaks detect` over the **full history**, not just HEAD.
  Grep for home-network details, internal hostnames (`appserv`), usernames (`svc_bob`), and email
  addresses. Decide what is fine to keep as history (the CHANGELOG narrative is a strength) and what isn't.
  Confirm the SOPS ciphertext still in history is harmless (the old key is lost, PR #1 rotated
  everything, and T02 retired those credentials entirely). Output: `docs/demo-prep/public-audit.md` with
  findings and actions.

#### T24 · Interactive "anatomy of an incident" page — *optional wow*
- A static page in the docs site (vanilla JS, no build step) that loads one real drill record JSON
  and draws the timeline: `t_inject → t_detect → t_classify → t_recover → t_verify`, then the
  DORA 4h/24h/72h/1-month and NIS2 24h/72h/1-month deadlines on a log-scale axis. Hovering an event shows
  the article. It turns the clocks divergence (the most DORA-literate point in the repo) into
  something visible in five seconds.

#### T26 · Rehearse twice (owner)
- Follow [`DEMO-SCRIPT.md`](DEMO-SCRIPT.md) end to end on a fresh VM, timing each section, with the
  fallback recording ready. Fix anything that surprised you; that becomes a new task.

### Phase F — teaching build-out: ISO 27001 and FedRAMP 20x High / DoD IL5 (after the demo)

**Owner direction, 2026-10-06:** grow this into the *architecture and bones* of an ISO 27001
and FedRAMP 20x High / IL5 programme. It is a **teaching tool, not a product.** It cannot achieve
either outcome: no audit, no 3PAO, no authorising official, no operating history, no maturity.
Every page must say so up front. Each product page also teaches the landscape: other projects
that could do the job, and the equivalent managed services on AWS, Azure and GCP.

Rules for every Phase F task:
- **Primary sources only** for regulatory content: ISO/IEC 27001:2022 (control *titles* only; the
  text is copyrighted), NIST SP 800-53 Rev 5 and the FedRAMP High baseline (official OSCAL JSON),
  FedRAMP 20x material on fedramp.gov, and the DoD Cloud Computing SRG from DISA. Cite URL and
  retrieval date. **FedRAMP 20x is still evolving** (it started as low/moderate pilots in 2025),
  so record which 20x release and KSI version you used, and flag anything about High that isn't
  published yet rather than inferring it.
- Never write "compliant", "authorized", or "certified" about this repo. Use "maps to",
  "demonstrates the mechanism for", or "would contribute evidence toward".
- Keep the P1 discipline: anything stated as *implemented* links to a file and, where possible, to
  generated evidence. Everything else is labelled *organisational*, *inherited from the cloud
  provider*, or *not addressed*.

#### F01 · "Alternatives & cloud equivalents" section on every component page
- **Files:** the 32 pages in `docs/components/` (from PR #3), `tests/test_docs_site.py`, and a new
  `docs/components/_template.md`.
- **Section to add** (fixed headings so a test can enforce it):
  - `## Alternatives` is a table: project, licence, maturity (CNCF graduated/incubating/sandbox or
    other), and one line on when you'd pick it instead. Three to six entries.
    Example for Velero: Kasten K10, Stash/KubeStash, CloudCasa, Trilio.
  - `## Managed cloud equivalents` is a table with AWS, Azure, and GCP rows: the service, what it
    covers, and **what it doesn't** (the shared-responsibility line). Example for Velero: AWS Backup
    for EKS, Azure Backup for AKS, Backup for GKE.
  - `## FedRAMP / IL5 note`: does that cloud service hold a FedRAMP High or IL5 authorisation in
    its government region? Link the FedRAMP Marketplace or provider page with a retrieval date.
    Write "unverified" rather than guessing.
- **Split into four sub-tasks of about 8 pages each**, so each fits one Sonnet session:
  - **F01a:** talos, kubernetes, cilium, argo-cd, helm, docker, storage, kyverno
  - **F01b:** cert-manager, keycloak, openldap-lam, sops-age, tetragon, trivy-operator, kube-bench, apko-wolfi
  - **F01c:** sigstore-cosign, github-actions, velero, minio, argo-workflows, alloy, loki, grafana
  - **F01d:** glpi, canary, drill-framework, evidence-pipeline, oscal, mitre-attack, mkdocs, testing
- **Done when:** the test fails if any component page lacks the three headings or the AWS/Azure/GCP
  rows, and `mkdocs build --strict` passes.

#### F02 · Cloud reference architectures (one page per provider)
- **Files:** new `docs/architecture/{aws,azure,gcp}.md`.
- **Steps:** for each layer of this lab (cluster, network policy, admission, PKI, identity, secrets,
  logging/SIEM, detection, vulnerability management, backup/DR, ITSM, evidence/compliance
  automation), name the native managed service on that provider. Note what you gain and lose versus
  the open-source build. Include each provider's *compliance-automation* services (e.g. AWS Audit
  Manager and Security Hub standards, Azure Policy regulatory-compliance initiatives, GCP Assured
  Workloads and Security Command Center) and which ISO 27001 / NIST 800-53 / FedRAMP High / IL5
  packs each offers, **verified against current provider docs**. Add a simple diagram per page
  (Mermaid, which MkDocs Material renders).

#### F03 · ISO 27001: from bones to an ISMS (teaching guide)
- **Depends on:** T15 (risk register + SoA).
- **Files:** new `docs/isms/` with `index.md` and one page per ISO 27001 clause, 4–10.
- **Steps:** for each clause (context, leadership, planning, support, operation, performance evaluation,
  improvement) explain three things. (a) What the clause demands, in plain English. (b) What this
  architecture already gives you: e.g. Clause 9.1 monitoring → measured drill metrics, Clause 8.2 risk
  assessment → T15's register, Clause 10 → post-incident review from drill records. (c) What only
  people can supply: management commitment, internal audit, management review, competence records.
  Then add an "ISMS year one" calendar, a RACI using the three-operator model from BUILD-SPEC §12, and
  the route to certification (Stage 1/Stage 2 audit, surveillance) with what an auditor would sample
  from this repo.

#### F04 · ISMS document skeletons (templates, clearly labelled)
- **Files:** `docs/isms/templates/`: information security policy, access control, cryptography
  (link `docs/guide/secrets-model.md` from T02c), backup and recovery, incident management (link the
  runbooks), supplier security (link the Register of Information), change management (link GitOps),
  logging and monitoring, vulnerability management (link the Trivy SLA).
- **Steps:** each template opens with a "TEMPLATE, not adopted policy" banner and has bracketed
  placeholders for organisation-specific decisions. Where this repo implements a policy statement,
  a "→ implemented by" link sits right next to it. That is the teaching point: policy statements tied
  to the control that enforces them and the evidence that proves it.

#### F05 · Machine-readable baselines: generated NIST 800-53 / FedRAMP High coverage
- **Files:** a new `compliance/` (or `docs/evidence/`) script `baseline_coverage.py`, a pinned
  download manifest, and tests.
- **Steps:** fetch NIST's official SP 800-53 Rev 5 OSCAL catalog and the official FedRAMP High
  baseline profile (OSCAL JSON) at **pinned commit SHAs with checksums**. Resolve the profile and join it
  against `docs/evidence/manifest.yaml`. Generate `docs/compliance/fedramp-high-coverage.md` and a
  JSON twin. Classify each control as *implemented with evidence*, *partially*, *inherited (cloud
  provider)*, *organisational*, or *not addressed*, from a hand-maintained `classification.yaml` that
  is small and reviewable. Expect most controls to land in organisational or not-addressed, and
  say so plainly; that honesty is the lesson. This supersedes the "representative subset" framing of
  `docs/06-nist-800-53-crosswalk.md`, which should then link to it.
- **Done when:** regeneration is deterministic (a test runs it twice and diffs), and the counts per class
  appear at the top of the page.

#### F06 · FedRAMP 20x: Key Security Indicators mapped to real evidence
- **Why this fits:** 20x replaces narrative-heavy packages with **automated, machine-readable
  validation** of Key Security Indicators. That is this repo's thesis ("measured, not asserted").
- **Files:** new `docs/compliance/fedramp-20x.md`, a `ksi` tag family in `manifest.yaml` (and
  `collect.py` support), and tests.
- **Steps:** pull the current published KSI list from fedramp.gov / the FedRAMP GitHub org and pin
  the version. For each KSI, record whether this repo has an **automated validation** (a script,
  drill, or policy whose output is a generated artifact), a manual one, or none. Tag existing evidence
  with KSI IDs so `by-control/ksi/…` folders generate like the other frameworks. Note where 20x's
  published scope stops short of High, flagged as such rather than inferred.
- **Stretch:** emit a 20x-style machine-readable validation summary alongside the OSCAL export, if
  FedRAMP has published a format. If it hasn't, write that down rather than inventing one.

#### F07 · DoD IL5 explainer: what IL5 adds on top of FedRAMP High
- **Files:** new `docs/compliance/il5.md`.
- **Steps:** from the DoD Cloud Computing SRG (cite the version), explain in plain English what
  Impact Level 5 is (CUI and unclassified National Security Systems) and what it adds beyond FedRAMP
  High: the additional DoD-specific controls/parameters, separation requirements from non-government
  tenants, personnel requirements, DoD PKI/CAC authentication, connection through DoD network
  boundaries, and incident reporting to DoD. For each, say what this architecture would need:
  - **Already shaped for it:** default-deny segmentation, admission control, signed images, hash-chained evidence.
  - **Buildable:** Keycloak X.509/CAC login, FIPS-validated crypto modules, DISA STIG checks for
    Kubernetes and the host OS, image provenance from a hardened registry.
  - **Never achievable in a lab:** a provisional authorisation, government-only tenancy, cleared personnel.
  Point to **Platform One / Big Bang and Iron Bank** as the DoD's own reference Kubernetes platform
  and hardened-image source, with a comparison table against this repo. Cloud options are AWS
  GovCloud (US), Azure Government, and Google Cloud's IL5 offerings, each verified against the
  provider's current IL5 listing.

#### F08 · Hardening evidence that IL5 and ISO both want (live)
- Absorbs Phase 14's `kube-bench` and Phase 26's crypto evidence, extended. Run kube-bench (CIS) on a
  schedule. Research and pin an open-source DISA Kubernetes STIG check, or write down that none is
  credible. Capture negotiated TLS versions and ciphers per served endpoint. Record FIPS status
  honestly: e.g. "Talos FIPS mode: [verified/not available] on this build", as Phase 23 did for SELinux.
  Each result becomes a hash-chained evidence sample tagged to ISO A.8.9/A.8.24, NIST CM-6/SC-13, and the
  relevant KSI.

#### F09 · "Use these bones to build your programme" capstone guide
- **Files:** new `docs/guide/build-your-programme.md`, linked from the docs home.
- **Steps:** a narrative for a reader at a real firm: start from scope and a risk register (T15), pick
  frameworks (DORA if you're an EU financial entity, ISO 27001 for certification, FedRAMP 20x/IL5 if you
  sell to US government), and adopt the evidence-manifest pattern so one control feeds many frameworks.
  Choose OSS versus managed per layer using F01/F02. Grow maturity from "documented" to "measured" to
  "continuously validated". Include a 12-month roadmap and a "what an auditor or AO will ask first" list.
  Then update the README and `docs/00-scope.md` framing to "a teaching reference architecture", and add
  Phase F to BUILD-SPEC §12 with the same honesty rules as above.

#### F10 · Hardening baselines library: servers and endpoints as config-as-code
**Owner direction, 2026-10-06:** the programme needs the estate *around* the cluster too. That means
Windows registry files for servers and endpoints, Linux system configuration, and hardening scripts.
These are the artifacts an ISO 27001 / FedRAMP / IL5 programme actually lives on (configuration
baseline: NIST CM-2/CM-6/CM-7; ISO A.8.9). Same rules as the rest of the repo: pinned, tagged to
controls, and **every baseline ships with a verify script whose output is generated evidence**,
not just an apply script.

**Layout:** a new top-level `baselines/`, one directory per target:
```
baselines/
  README.md                      # how to read/apply/verify; licensing notes; exception process
  linux/ubuntu-24.04/            # sysctl.d, auditd rules, sshd_config.d, pam, chrony, aide, modprobe.d
  linux/rhel-9/                  #   + an Ansible role applying them, and verify.sh
  windows/server-2022/           # .reg files, a GPO-equivalent PowerShell DSC config, auditpol export, verify.ps1
  windows/11-endpoint/           # .reg + Intune Settings Catalog JSON + Defender/ASR config, verify.ps1
  macos/                         # optional: a NIST mSCP-generated profile
  mappings.yaml                  # setting -> STIG ID / CIS rec number / NIST / ISO / KSI
```

**Licensing (teach this, it's a real-world trap):** DISA STIG content is US-government work and
can be reused. **CIS Benchmark text is licensed.** Reference CIS recommendation *numbers* only,
never their prose. Microsoft Security Baselines (Security Compliance Toolkit) can be referenced and
compared against; link them rather than vendoring.

**Sub-tasks**, each one Sonnet session:

- **F10a · Scaffold and mapping schema.** Create `baselines/README.md`, the `mappings.yaml` schema
  (with a JSON Schema and a test), and teach the exception process: a deviation from the baseline is a
  committed file with a reason, an owner, and an expiry, the same P2 discipline as `docs/exceptions/`.
  Add `baselines` to `docs/evidence/manifest.yaml` tagging, and a `stig`/`cis` tag family in `collect.py`.
- **F10b · Ubuntu 24.04 server baseline.** Config files plus an idempotent Ansible role (pinned
  collections), from the DISA Ubuntu 24.04 STIG and CIS Level 1 Server (numbers only). Verify with
  **OpenSCAP + SCAP Security Guide** (pinned release) and a short `verify.sh` for anything SSG
  doesn't cover. CI: apply and scan inside an Ubuntu 24.04 container or GitHub runner. The SCAP
  results (ARF/HTML) become a hash-chained evidence sample. Compare against `ansible-lockdown`
  (UBUNTU24-STIG/CIS) in the README alternatives table.
- **F10c · RHEL 9 (or Rocky/Alma 9) server baseline.** Same pattern. SSG ships an official RHEL 9
  STIG profile and Ansible remediation, so show *generating* the remediation from SSG versus
  hand-writing it. That comparison is the lesson.
- **F10d · Windows Server 2022 baseline.** `.reg` files (one per policy area, commented with STIG
  V-IDs), a PowerShell DSC configuration as the GPO-equivalent apply path, `auditpol` advanced audit
  settings, and `verify.ps1` emitting JSON per setting (expected / actual / pass). CI applies and
  verifies on a **`windows-2022` GitHub-hosted runner**, so it's real verification without owning a
  Windows box, and the JSON becomes evidence. Note what a runner can't prove (domain GPO
  precedence, LAPS, AD-joined behaviour). Compare against Microsoft's Server 2022 Security Baseline
  and DISA's STIG GPO package in the README.
- **F10e · Windows 11 endpoint baseline.** `.reg` + an Intune Settings Catalog JSON export (for the
  MDM path) + Defender for Endpoint / ASR rules + BitLocker + Credential Guard settings, plus
  `verify.ps1`. Explain GPO vs. Intune vs. registry: same setting, three delivery mechanisms, and which one a
  modern estate uses. CI verifies on a `windows-latest` runner where possible and labels what needs real
  hardware (TPM, Secure Boot) as unverifiable.
- **F10f · Cluster-node baseline (ties back to the lab).** Bring Talos's own config (`platform/talos/patches/`)
  and the kube-bench/STIG results from F08 into the same `mappings.yaml`. Then one table shows every
  layer (Talos node, Ubuntu host, Windows server, Windows endpoint) against the same control IDs.
- **F10g · Drift detection.** A scheduled CI job re-runs every verify script weekly (same cadence as the
  image rebuild) and appends results to the evidence chain. Drift opens a GLPI ticket or a GitHub
  issue. That turns baselines from "applied once" into "continuously validated", the FedRAMP 20x idea.

**Done when (each sub-task):** apply is idempotent (running it twice changes nothing on the second
run, tested in CI); verify emits machine-readable results; every setting has a `mappings.yaml` row;
and the README states which controls are *not* covered.

---

## 5. Prompt template for handing a task to Sonnet

```text
You are working in the dora-blueprint repo. Read BUILD-SPEC.md §1 (principles P1–P8) and
docs/demo-prep/TASKS.md first. Your task is <TASK ID AND TITLE> from TASKS.md. Do only that task.

Rules:
- Work on a new branch named <prefix>/<short-name> off main. Commit with clear messages.
- Run the offline test suite (pytest) and `make evidence-verify` before every push.
- Pin every version you add. Never commit plaintext secrets. Never edit or delete files in
  docs/evidence/samples/ (append-only, hash-chained).
- Add a CHANGELOG.md entry. If you find something broken outside the task, write it down in
  the PR description; don't fix it.
- If the task says "live" and you have no cluster, stop after the offline part and list exactly
  which commands the owner must run on the VM.
When done, open a PR against main whose description lists the acceptance criteria from
TASKS.md and how each was verified.
```
