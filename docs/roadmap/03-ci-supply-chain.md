# Track 03: CI and supply chain

Two tasks. T07 makes CI live up to the project's own pinning rule (P3), and closes gap G18. T25 boots
the real platform inside GitHub Actions, so most bring-up breakage is found before anyone pays for a VM.

---

## T07 · Pin CI tooling by version and commit SHA

- **Wave / mode:** 1 · offline
- **Depends on:** PR #2 merged (it adds `tests.yaml` and `docs.yaml`)

**Read first:** every file in `.github/workflows/`, and GitHub's security hardening guide for Actions
(the section on pinning to a full-length commit SHA).

**Steps:**
1. Replace `go install chainguard.dev/apko@latest` in `build-images.yaml` with a pinned apko release binary:
   download from the GitHub release, verify its checksum (from the release's checksums file, the checksum itself
   pinned in the workflow), and install to `$RUNNER_TEMP/bin`. Remove `actions/setup-go` if nothing else needs it.
2. Pin every `uses:` to a full 40-character commit SHA with a trailing `# vX.Y.Z` comment. Resolve each SHA from
   the action's release tag with `git ls-remote https://github.com/<owner>/<repo> refs/tags/<tag>`. For annotated
   tags, use the peeled `^{}` commit.
3. Pin tool versions passed as inputs: cosign (`cosign-release:`), syft through `anchore/sbom-action`'s
   `syft-version`, the Python version, and mkdocs and its plugins through `requirements-docs.txt` with `==`.
4. Add `.github/dependabot.yml` for `github-actions` (weekly), so the SHAs get bumped through reviewed PRs.
   That turns pinning into a maintained control rather than a frozen one.
5. Set `permissions:` at the workflow level to the minimum, and widen per job only where needed (`id-token: write`
   and `packages: write` only on the signing job).

**Tests** (`tests/test_ci_pinning.py`):
- Every `uses:` matches `^[\w.-]+/[\w./-]+@[0-9a-f]{40}$` (local `./` actions excepted).
- No workflow contains `@latest`, `version: latest`, `go-version: stable` or `:latest`.
- Every workflow declares top-level `permissions`.

**Done when:**
- [ ] Tests pass, and the workflows still parse (`actionlint`, pinned, run in CI).
- [ ] A `workflow_dispatch` run of `build-images.yaml` succeeds, with a link in the PR. If you can't trigger it,
  list the owner's steps.
- [ ] G18 is closed in the gaps register, and the DORA sheet row for 9(4)(f) is updated and re-rendered.

---

## T25 · CI smoke bring-up of the `core` tier

- **Wave / mode:** 2 · runs in CI
- **Depends on:** T02b (no secrets needed to stand up), T03 (no hard-coded LAN address), and D5 (a public repo
  gets the larger standard runners and needs no Git credential for Argo CD)

**Why:** every phase in the CHANGELOG found "caught live" bugs, so bring-up is where risk concentrates. A CI job
that really boots the platform catches those bugs on every relevant PR, for free, without the demo VM. It doesn't
replace T17. Runners are smaller and short-lived, and the job runs `core`, not `full`.

**Read first:** `bootstrap/install.sh` (and the `WORKERS`, `MEMORY_CONTROLPLANES` and `MEMORY_WORKERS` knobs from
PR #1), `apps/core/`, `drills/lib/run-drill.sh`, Talos's docs on `talosctl cluster create` with the Docker
provisioner, and GitHub's documentation on standard hosted-runner specs for public and private repositories
(check the current figures; don't assume).

**Files:** new `.github/workflows/smoke-bringup.yaml`, new `scripts/ci/wait-for-argocd.sh`, and edits to
`install.sh` only if needed. Prefer env knobs, not CI-specific branches in the script.

**Steps:**
1. Triggers: `workflow_dispatch`; `pull_request` when paths under `bootstrap/**`, `apps/**`, `infrastructure/**`,
   `drills/**`, `canary/**` or `platform/**` change, *and* the PR carries the label `smoke`, so heavy runs are
   opt-in; and a weekly schedule.
2. Resource gate: the first step prints `nproc`, `free -g` and `df -h`. If memory is under 14 GB, fail with a
   message explaining the runner is too small, rather than flaking later.
3. Free disk space on the runner (remove the preinstalled toolchains you don't need) and install the pinned
   talosctl/kubectl/helm through `prepare-host.sh` (no `--tailscale`).
4. Bring up with `WORKERS=0 MEMORY_CONTROLPLANES=<fits the runner> TIER=core ACCESS_HOST=127.0.0.1
   TARGET_REVISION=${{ github.event.pull_request.head.sha || github.sha }} make lab-core`. Argo CD must sync the
   **commit under test**, not `main` (T02b adds `TARGET_REVISION`).
5. `wait-for-argocd.sh`: poll `kubectl get applications -n argocd` until every Application is `Synced` and
   `Healthy`, or a timeout (default 40 minutes). On timeout, print a table of each app's sync and health status,
   with the last conditions and events for unhealthy ones.
6. Assertions: the canary is writing (its counter increases over 30 seconds); all cert-manager `Certificate`s are
   Ready; Kyverno denies a privileged test pod; a Cilium default-deny check blocks a disallowed flow.
7. Stretch: run `make drill SCENARIO=ns-restore`, upload the drill record as a workflow artifact, and print RTO/RPO
   in the job summary. **Do not commit it as evidence.** CI-produced records are useful but aren't the curated
   samples. Let the owner decide in T19 whether CI records become a tagged evidence class.
8. Always (an `if: always()` step): collect `kubectl get events -A`, the Argo CD app statuses and pod logs for
   failed pods into an artifact, then `talosctl cluster destroy`. Set a job timeout of 90 minutes.
9. Write the job summary as a Markdown table: app → status, time to healthy, total bring-up time.

**Done when:**
- [ ] The workflow parses, and is pinned per T07.
- [ ] One real run is attached to the PR. Either it's green, or every failure is root-caused into a follow-up issue
  (one issue per distinct failure, labelled `smoke`). A red first run is expected and acceptable, as long as each
  failure is diagnosed.
- [ ] `docs/guide/demo-vm.md` gains a "CI smoke test" section explaining what it does and doesn't prove.

**Out of scope:** the `full` tier in CI (too heavy for standard runners), and fixing the bugs it finds (open issues
instead, unless the fix is a one-liner in a file the PR already touches).
