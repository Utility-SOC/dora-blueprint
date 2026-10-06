# Track 06: showcase and narrative

What a hiring manager, a head of ICT risk, or a CISO actually sees: the README, the published docs site,
a few visuals that land in five seconds, and a rehearsed live demo. The talk track is
[`demo-script.md`](demo-script.md).

**Order:** T16, T13, T14 and T24 any time in wave 2. T23 → T22 after wave 3. T26 last.

---

## T16 · README: demo-first front page, no stale claims

- **Wave / mode:** 2 · offline
- **Depends on:** PRs #1–#4 merged (they touch the README), ideally T11 (so the "on a schedule" claim is true)

**Read first:** `README.md`, `BUILD-SPEC.md` §10 ("put the tiering table at the very top of the README … the recording
is what actually gets seen"), and the generated "DORA, article by article" block. **Never hand-edit that block.**
Leave it between its markers.

**Steps:**
1. Remove false or stale claims:
   - the "Observability" section saying the `full` profile "adds Elastic/Fleet/eBPF". The full tier is Tetragon,
     Trivy and IAM, with no Elastic.
   - any statement made untrue by tracks 01–04 (SOPS, the offline root, `192.168.1.106`).

   Grep for each claim and check a file implements it (P1).
2. New top-of-page order:
   1. Title and a three-sentence pitch: what it is, the thesis, and what it isn't.
   2. One hero image: the RTO/RPO trend from T20. Leave a placeholder comment until T20 lands.
   3. "Watch a drill": the asciinema GIF/SVG from T20.
   4. A 60-second tour of six links: executive summary, one drill record explained, DORA coverage (the generated
      section and the CSV), the gaps register, the docs site, and the demo script.
   5. Tier table and quick start, including the cloud-VM path (`docs/guide/demo-vm.md`).
   6. What's running.
   7. DORA, article by article (generated).
   8. Status, short. Move the 28-row phase table and the roadmap prose to `docs/history/phases.md`, and link
      `docs/roadmap/` for what's ahead.
3. Keep it to about two screens above "DORA, article by article".
4. Add a "Teaching tool, not a product" box near the top, linking `docs/04-limitations.md`.

**Tests:** add to `tests/test_repo_consistency.py`:
- the README contains no `Elastic/Fleet`;
- every relative link in the README resolves;
- the DORA block is up to date (`dora_readme.py --check`).

**Done when:** tests pass and the PR has a screenshot of the rendered README on GitHub.

---

## T13 · Alert notifications to a real channel (gap G8) · optional, good on stage

- **Wave / mode:** 2 · offline, with a live proof in T19
- **Depends on:** T02b

**Steps:**
1. Add a Grafana contact point and notification policy through provisioning in `apps/core/grafana.yaml`, routed to a
   webhook whose URL comes from a Secret created at stand-up from the env var `ALERT_WEBHOOK_URL`. If the variable is
   unset, there's no contact point, and the default stays silent.
2. Document two options: an `ntfy.sh` private topic (zero setup, push to phone) or a Microsoft Teams/Slack incoming
   webhook (what Irish financial firms typically use).
3. Route only the two detection rules and T11's drill-staleness alert. Include the runbook URL and ATT&CK technique in the
   message template.
4. Update the DORA sheet row 10(2) and close G8 as "fixed, pending live".

**Done when:** the provisioning YAML validates, and the live check is listed for T19 (the phone buzzes during the
credential-compromise drill).

---

## T14 · MFA for operators (gap G7) · optional, a strong signal for finance audiences

- **Wave / mode:** 2 · offline, with a live proof in T19
- **Depends on:** T02b

**Steps:**
1. In `infrastructure/keycloak/configure-realm.sh`, create a conditional authentication flow requiring OTP (TOTP) for members
   of the platform-operator group, bound as the realm's browser flow. Make it idempotent on re-run.
2. Break-glass: a documented emergency path. For example, a separate master-realm admin without MFA, whose credentials
   live only in the generated `credentials.txt`, and whose use is logged and alerted. It is explicitly an exception (P2
   file in `docs/exceptions/`).
3. Optional: WebAuthn as a second option, for the teaching note.
4. Update `docs/03-control-matrix.md`, the DORA sheet row 9(4)(d) and the NIST crosswalk (IA-2(1)). Close G7 as "fixed,
   pending live".

**Done when:** the script runs twice cleanly against a fake API in tests (or with live steps listed), and the exception file is committed.

---

## T24 · Interactive "anatomy of an incident" page · optional, the visual moment

- **Wave / mode:** 2 · offline
- **Depends on:** T10 (all deadlines exist); PR #3 merged (docs site)

**Steps:**
1. `docs/incident-anatomy.md` plus `docs/assets/incident-anatomy.js`, in vanilla JS with no build step and no external CDN
   unless pinned with SRI.
2. Load one real enriched drill record (a JSON file copied into `docs/assets/`, not edited) and draw a horizontal
   timeline:
   - events: `t_inject → t_detect → t_classify → t_recover → t_verify`;
   - deadline lanes: DORA (initial 4h / 24h cap, intermediate, final) and NIS2 (24h, 72h, one month);
   - a log-scale time axis, so seconds and months both fit.
3. Hovering or tapping an event shows its definition and legal basis. A toggle highlights the core point: **DORA's clock
   starts at classification, NIS2's at awareness.**
4. It must work on mobile, in light and dark mode, and print legibly.

**Tests:** a small Node-free check, e.g. Python asserting the page references an existing record file and that every
field it reads exists in the schema.

**Done when:** it renders in `mkdocs serve`, and the PR has screenshots (desktop and mobile).

---

## T23 · Public-readiness audit

- **Wave / mode:** 4 · offline
- **Depends on:** tracks 01–04 merged

**Steps:**
1. Run a secret scan over the **full history**: `gitleaks detect --log-opts="--all"` (pinned), plus GitHub secret scanning
   if available. Triage every hit.
2. Grep the full history (`git log -p --all`) for home-network details (`192.168.`), internal hostnames (`appserv`),
   usernames (`svc_bob`), email addresses, and anything personal. Decide per item: harmless history (the CHANGELOG
   narrative is a strength), or something to remove from HEAD.
3. Confirm the SOPS ciphertext still in history is harmless: the key is lost, the credentials were rotated (PR #1), and
   track 01 retired them.
4. Check licences: a `LICENSE` file exists (ask the owner which licence; Apache-2.0 is a sensible default for a
   reference architecture), and third-party content is attributed. Confirm no copyrighted standard text (ISO, CIS) is
   reproduced beyond titles and numbers.
5. Write the result to `docs/roadmap/public-audit.md`: findings, decisions, and the actions taken. **History rewrites
   need the owner's explicit approval.** Recommend; don't do it.

**Done when:** the audit doc is merged and the owner has signed off on making the repo public (D5).

---

## T22 · Publish the docs site

- **Wave / mode:** 4 · offline
- **Depends on:** T23, D5

**Steps:**
1. Enable the GitHub Pages deploy job from PR #3. Set `site_url`, and check `mkdocs build --strict`.
2. Add a landing page, "For hiring managers: the 5-minute tour":
   - the executive summary;
   - one drill record explained line by line;
   - the incident anatomy page (T24);
   - DORA coverage (render the CSV as a sortable table page);
   - the gaps register;
   - the demo recording.
3. Add social preview metadata (title, description, image from T20).
4. Link the site from the README top and the repo "About" box (owner action).

**Done when:** the site is live, a link checker passes on it (pinned `lychee` in CI), and the URL is in the README.

---

## T26 · Rehearse the demo twice (owner)

- **Wave / mode:** 4 · owner, on the live VM
- **Depends on:** wave 3 complete

Follow [`demo-script.md`](demo-script.md) end to end, twice, on a VM stood up fresh from T08's procedure. Time each section
against the running-order table. Each time, check the ⚑-marked facts against current sources that week. Note everything that
surprised you, and each surprise becomes a new task. Record one full rehearsal as a backup video.
