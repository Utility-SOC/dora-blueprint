# Track 07: live bring-up and fresh evidence

The only track that needs the cloud VM. It's best run by an agent **on the VM itself** (D7: install Claude
Code there), with the owner watching. Every fix goes back into Git, and Argo CD syncs it. Nobody hot-patches
the cluster (CONVENTIONS §7).

**Order:** T17 → T18 → T19 → T20 → T21. T17 is likely to take several sessions; that's expected.

**Before starting**, these should be merged: tracks 01 and 02 (secrets, access host, port-forwards, image pull,
cloud-init); ideally track 04 (so the fresh evidence reflects the fixed verdict, clocks and RPO logic); and T25 green,
or its failures understood.

---

## T17 · First cloud bring-up

- **Mode:** live
- **Depends on:** D2, D3, D7, and the merged tracks above

**Steps:**
1. Provision with `bootstrap/cloud/hetzner.sh create` (or another provider). Record the provider, region, size, image and
   hourly price.
2. On the VM: `TS_AUTHKEY=… bash bootstrap/prepare-host.sh --tailscale`, then
   `bash bootstrap/set-access-host.sh <tailscale-ip>`, then commit and push that change, then
   `bash bootstrap/preflight.sh`. Preflight must report 0 failed.
3. `time make lab-full 2>&1 | tee ~/bringup-$(date -u +%Y%m%d%H%M%S).log`. Record the duration of each of `install.sh`'s
   numbered steps.
4. `bash bootstrap/port-forwards/install.sh`. From the laptop over Tailscale, open every UI in the access map
   (`docs/roadmap/02-cloud-hosting.md`). Log into Argo CD and Grafana through Keycloak with the generated credentials
   (`~/.dora-blueprint/credentials.txt`).
5. Run the live checks that the earlier PRs listed. Collect them from the "Live verification" sections of the T02a, T02b,
   T03, T04, T06, T09, T11, T12, T13 and T14 PRs:
   - certificate chain (`openssl s_client -showcerts`);
   - Kyverno denial;
   - Cilium default-deny;
   - canary writing;
   - `kubectl get applications -n argocd`: all Synced/Healthy.
6. **For each failure:** collect the evidence (events, logs, `kubectl describe`), find the root cause, fix it in Git on a
   branch, open a PR, merge it, and let Argo CD sync. Add a CHANGELOG "caught live" entry. Keep a running table in the
   T17 PR with the symptom, root cause, fix PR and minutes lost.
7. When it's healthy: **destroy the VM and repeat from scratch** (BUILD-SPEC Phase 1: "works twice in a row from clean").
   Record the second bring-up's time too.
8. Update `docs/guide/demo-vm.md` with the real timings, real cost, and every gotcha found.

**Done when:** two clean bring-ups have been recorded, with all apps Healthy and all the listed live checks passing. The live
checks become a committed evidence sample, `bringup-verification-<ts>.txt`.

---

## T18 · Prove the generated API tokens work end to end (gap G19)

- **Mode:** live
- **Depends on:** T17

**Steps:**
1. Confirm `install.sh` minted the GLPI and Grafana tokens unattended (the Secrets exist and were created by this run;
   check timestamps).
2. Run `make drill SCENARIO=ns-restore` and confirm a real GLPI ticket opens with classification and the deadline table.
3. Confirm the Grafana alerting configuration applied (the rules exist with their ATT&CK labels).
4. Check the Trivy findings exporter is producing data (the vulnerability dashboard is populated, and the KEV column is non-empty
   or legitimately zero).
5. Commit an evidence sample covering these checks. Close G19.

**Done when:** the evidence sample is committed and tagged in the manifest, and G19 is closed.

---

## T19 · Fresh evidence on current code (gaps G20, G15, G4 and others)

- **Mode:** live
- **Depends on:** T18

**Steps:**
1. Run all five scenarios. Run `ns-restore` **three times** and record the RTO spread (min, median, max).
2. Let each CronWorkflow (T11) fire at least once. Pause one and confirm the staleness alert fires, then resume it.
3. Verify the live parts of earlier tasks:
   - verdicts reflect targets (T09);
   - deadlines present in records and tickets (T10);
   - RPO ≥ 0 and incarnation ids match (T12);
   - phone notification on the credential-compromise drill (T13), if built;
   - an MFA prompt on login (T14), if built.
4. Copy the new records and outputs into `docs/evidence/samples/` (new files only), tag them in `manifest.yaml`, run
   `make evidence`, and commit.
5. Update the gaps register (close G4, G15 and G20, plus any marked "pending live") and the DORA sheet rows whose evidence
   column should now cite fresh samples. Re-render the README.

**Done when:** every "pending live" item is closed or explicitly re-opened with a reason, and the chain verifies.

---

## T20 · Screenshots and recordings (BUILD-SPEC Phase 15)

- **Mode:** live
- **Depends on:** T19 (so the dashboards show real history)

**Capture, at 1600×1000 in the browser's light theme**, plus dark variants for the hero images:

| # | Shot | Shows |
|---|---|---|
| 1 | Argo CD application tree | GitOps; everything reconciled |
| 2 | Grafana RTO/RPO trend | measured, repeated (the hero image) |
| 3 | Grafana "last successful drill per scenario" | it runs on a schedule |
| 4 | Vulnerability dashboard with the KEV column | Art. 13 / A.8.8 |
| 5 | The detection alert firing, with its ATT&CK label | Art. 10 |
| 6 | A GLPI ticket with the DORA vs NIS2 deadline table | Art. 17–19 |
| 7 | Hubble showing a dropped flow | Art. 9(4)(b) |
| 8 | Terminal: Kyverno denying a privileged pod | Art. 9 |
| 9 | Terminal: `make evidence-verify` pass → tamper → fail | evidence integrity |

**Recording:** `asciinema rec` of `make drill SCENARIO=ns-restore` (trim idle waits in post with `asciinema-edit` or similar,
pinned), converted to GIF or SVG with `agg` (pinned). Keep it under 60 seconds after trimming, and say on screen that it was sped up.

**Storage:** put everything under `docs/assets/screens/`, with a `README.md` giving the date, git SHA and what each image shows.
Check every image for secrets, tokens, internal IPs and personal data before committing. Embed them in the README (T16 slots) and
the docs site. Optimise PNGs (e.g. `oxipng`, pinned).

**Done when:** all nine shots and the recording are committed, reviewed for sensitive content, and embedded.

---

## T21 · Teardown, snapshot, cost guard

- **Mode:** live
- **Depends on:** T20

**Steps:**
1. `make demo-down`:
   - copies any uncommitted evidence off the VM (e.g. `rsync` to the laptop) and warns if anything wasn't committed;
   - then calls the provider's destroy command (from T08) with confirmation.
2. Document the snapshot option: create a provider snapshot of a healthy VM as a rollback point the night before a talk,
   and restore it on the day. Record the real snapshot cost and the time to restore versus a fresh bring-up.
3. Check that the T08 idle-poweroff timer worked during the bring-up sessions (its logs), and record the real total spend.

**Done when:** `demo-down` is tested on a real teardown, and the costs are in `docs/guide/demo-vm.md`.
