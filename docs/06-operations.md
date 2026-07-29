# Operations: usage, change procedures, evidence handling

This document answers three questions a reviewer or a real operator would ask that the
control matrix and shared-responsibility doc don't cover: how do you actually run this thing
day to day, what's the change procedure when something needs to be modified, and what happens
to the evidence this repo generates. It's written against the platform as it exists today
(Phase 9 complete, Phase 11 in progress) — sections below say plainly where the real answer is
"not built yet" rather than describing an aspirational process.

## 1. Bringing the lab up and using it

- `make lab-core` runs `bootstrap/install.sh` — the one manual-apply exception build-spec P4
  allows. It's idempotent (safe to re-run) and brings up: Talos cluster → Cilium → Argo CD →
  the `platform` AppProject → `root-app` (the app-of-apps). From that point on, everything else
  is GitOps-managed; `bootstrap/install.sh` only re-runs when a *secret* needs creating or an
  Argo CD ConfigMap needs a non-Helm-managed patch (steps 7–12 — cert-manager's Intermediate CA,
  IAM secrets, Argo CD OIDC/RBAC config, MinIO/Velero credentials, Grafana's alerting API token,
  GLPI/MariaDB credentials). See the script's own header comments for exactly which steps those
  are and why each one can't be expressed as a synced manifest.
- `make drill SCENARIO=<name>` runs a drill (currently `ns-restore`; more scenarios land in
  Phase 10) via `drills/lib/run-drill.sh`, which also classifies the result, computes both
  regulatory clocks, and opens a GLPI ticket (Phase 11) after a successful run. Output is a drill
  record — see `drills/schema/drill-record.schema.json` — printed to stdout and, for now,
  manually promoted to `docs/evidence/samples/` when it's worth keeping as citable evidence
  (§3 below).
- `make lab-full`, `make lab-dr`, `make evidence`, `make images` all exist as stubs today and
  fail loudly rather than silently no-op — build-spec P1 ("no claim without an implementation").
  Don't trust a green run of these; they're not implemented yet.
- **Accessing the UIs**: nothing in this lab has a real network-level Ingress yet — every UI
  (Argo CD, Grafana, Keycloak, Hubble) is reached via `kubectl port-forward --address
  192.168.1.106 ...`, which is confirmed (Phase 6) to bypass Cilium's CNI enforcement entirely on
  both ends. This is a known, documented gap, not an oversight — see the jumphost/bastion item in
  §4.
- **Credentials**: every credential this lab uses is SOPS-encrypted at rest
  (`infrastructure/*/secrets/*.enc.yaml`, `age` recipient in `.sops.yaml`) and only exists as a
  real Kubernetes Secret because `bootstrap/install.sh` decrypted and applied it. There is no
  plaintext credential committed anywhere in this repo — if you ever find one, that's a bug, not
  a shortcut.

## 2. Change procedure

There is no CI pipeline and no branch protection on this repo today — every change lands via a
direct commit/push to `master`, and Argo CD's `selfHeal: true` picks it up automatically. That's
a deliberate scope cut for a reference lab with one operator, not a recommendation: a real
deployment of this pattern would gate every merge behind CI (manifest linting, `kubeconform`/
`kyverno test`, a `sops` pre-commit check that no plaintext secret is staged) and branch
protection requiring review, the same way any production GitOps repo would. That's flagged here
as a real, current limitation rather than silently assumed away.

**The general flow, for any change:**

1. Edit the manifest(s) under `infrastructure/` or `apps/` (or `platform/talos/` for
   node-level config, which requires a `talosctl apply-config` — not just a git push, since Talos
   config isn't Argo CD-managed).
2. Commit and push to `master`.
3. Argo CD syncs automatically (`selfHeal: true` on every `Application`). **Known gotcha, hit
   repeatedly in this repo's own history**: `apps/*.yaml` Application resources are themselves
   synced by `root-app` (the app-of-apps). If you changed an *Application's own spec* (new Helm
   values, a new sync-wave, a new source path) rather than a resource *inside* the directory it
   points at, `root-app` has to sync first before that change takes effect — `argocd app sync
   root-app`, then the target app. If a change isn't showing up, check this before assuming
   something is broken.
4. Verify against real behavior, not a clean sync status — this repo's own recurring lesson,
   documented at least half a dozen times across `README.md`'s phase notes: a `Synced`/`Healthy`
   status has repeatedly not meant the real behavior matched (Velero silently restoring an empty
   volume, Grafana's `extraVolumes` silently becoming an `emptyDir`, Cilium's audit-mode not
   actually staying non-enforcing). Run the actual functional test the change is supposed to
   enable before calling it done.

**Higher-risk change classes get an extra step:**

- **Cilium `CiliumNetworkPolicy` changes** — audit-mode first
  (`policy.cilium.io/audit-mode: "true"`), a real Hubble capture window against actual traffic,
  *then* flip to enforcing and re-verify with a functional test. Note the repo's own confirmed
  finding: audit-mode on this Cilium version (v1.19.6) has not reliably stayed non-enforcing —
  treat it as advisory, not a guarantee, and don't skip the post-enforcement functional check.
  `kube-system` policies are the one exception to "everything is GitOps" — see
  `infrastructure/cilium/kube-system/README.md` for why, and apply them with `kubectl apply`
  directly, git-tracked for review.
- **Kyverno policy changes** — same audit-then-enforce discipline. If a workload needs an
  exception, it gets a written rationale in `docs/exceptions/<name>.md` (see the existing five
  for the expected format) *before* the exception is added to the ClusterPolicy, not after.
  Prefer a `PolicyException` object; fall back to a ClusterPolicy `exclude` block only for a
  pod-level (not container-scoped) violation, per the confirmed open bug
  [kyverno/kyverno#12888](https://github.com/kyverno/kyverno/issues/12888).
- **Secret rotation** — decrypt the existing `.enc.yaml` with `sops --decrypt`, edit the
  plaintext value, re-encrypt with `sops --encrypt --in-place` (must run from a directory under
  `.sops.yaml`'s scope), commit the re-encrypted file, then re-run the relevant
  `bootstrap/install.sh` step (or the whole script — it's idempotent) to push the new value into
  the live cluster as a real Secret. Rotating a credential that other config references by value
  rather than by `secretKeyRef` (rare in this repo, but check) means also bumping whatever
  consumes it.
- **`bootstrap/install.sh` itself** — the one part of this repo that isn't picked up by a git
  push. A change here only takes effect on the next manual `make lab-core` re-run; document that
  explicitly in the commit message so a reader doesn't assume `git push` alone was sufficient.

## 3. Do you need a ticketing system?

**Yes, and this platform now runs one: GLPI, self-hosted on the same cluster as everything
else** (`infrastructure/glpi/`, build-spec Phase 11). Earlier drafts of this doc argued GitHub
Issues was "the right amount of ticketing" for a single-operator lab — that held up until the
GitHub-token setup step surfaced the real question ("why GitHub specifically?") and the honest
answer was "zero new infrastructure," not "the right tool." Once a real self-hosted ITSM tool
was on the table, it was a deliberate, not incidental, choice: this repo already self-hosts
Keycloak, OpenLDAP, Grafana, and MinIO — nothing else here calls out to a SaaS product for a
core function, and ticketing shouldn't be the one exception.

**Why GLPI specifically**, over a lighter ticketing-only tool: it's a real ITSM/ITIL-shaped
product (Incident/Problem/Change/Service Request as first-class objects), has a mature Docker
deployment story (official `glpi/glpi` image, weekly security rebuilds), a real REST API, and —
the deciding factor — its asset-management module is a legitimate future source for DORA
Art. 28's Register of Information (build-spec's own later supply-chain phase). A pure ticketing
tool would only ever serve incident response; GLPI sets up a second real payoff without being
asked to do anything it isn't already designed for.

The drill/detection pipeline emits a structured record (`drills/schema/drill-record.schema.json`)
regardless of destination — `drills/lib/enrich.py` computes classification and both DORA/NIS2
deadlines from real timestamps, and `drills/lib/open-incident.py` is the one place that record
gets turned into a ticket (GLPI's `initSession` → `Ticket` REST flow). That's still a real,
isolated boundary: swapping GLPI for a different self-hosted tool, or a real organization's
existing ITSM system, is a change to that one file, not to anything upstream of it.

## 4. Where does the evidence get parsed?

**Nowhere, automatically, today** — that's a real, current gap, not a hidden one.
`docs/evidence/samples/` holds the evidence artifacts this repo has generated so far (drill
JSON records, captured Hubble/kubectl/openssl output, decoded tokens), and
`docs/03-control-matrix.md` links each control row to the specific file that backs it — by
hand. A human (in this session, me) ran the verification command, read the real output, decided
it was worth keeping, and copy-pasted or saved it into that directory with a timestamped
filename. There is no aggregator, no dashboard, and no automated report generator consuming
those files today.

That's explicitly the gap build-spec Phase 14 closes: **"evidence report generator... `make
evidence` produces the report."** The intended design (not yet built, so treat this paragraph as
a plan, not a capability) is a script that walks `docs/evidence/samples/` plus whatever
structured drill records exist under the gitignored `docs/evidence/` working directory (see
`platform/talos`-adjacent `.gitignore` — only `samples/` is committed, the rest is
generated/ephemeral per build-spec's repo layout), cross-references them against
`docs/03-control-matrix.md`'s rows, and renders a single report — the artifact build-spec §13
calls out by name as what a reviewer who never deploys this lab should be able to see directly
in the README (an asciinema recording, an RTO/RPO trend chart, "a sample generated evidence
report").

Two things worth being explicit about in the meantime, since "not built yet" doesn't mean
"unusable now":

- **The control matrix itself is the parse target today.** It's not a placeholder waiting for
  automation — read as a table, it already answers "what evidence backs this control" for every
  row currently marked `generated`, with a direct link to the real artifact. The automation in
  Phase 14 makes that easier to consume in bulk (a trend over many drill runs, a single exported
  PDF/HTML for an auditor); it doesn't change what's true today.
- **Evidence write-once/tamper-evidence** (build-spec P7: "Logs an admin can silently delete
  are not evidence") is itself not implemented yet — today's evidence samples are plain
  git-tracked files, which means git history is the only tamper-evidence property they currently
  have (a deleted or edited sample shows up as a diff). Real write-once guarantees (ILM,
  write-only ingest role, object-locked storage snapshots) are scoped to the detection-layer
  work (Phase 9) and haven't landed. Don't cite this repo's evidence as tamper-proof beyond "it's
  in git history" until that phase lands.

## 5. Summary

| Question | Today | Planned |
|---|---|---|
| How do I bring the lab up? | `make lab-core` (idempotent, re-runnable) | — |
| How do I make a change? | Direct push to `master`, Argo CD auto-syncs; higher-risk classes (Cilium, Kyverno, secrets) get an audit-first or decrypt/re-encrypt step, per §2 | CI + branch protection (not built — single-operator lab today) |
| Do I need a ticketing system? | Yes — GLPI, self-hosted on this cluster (Phase 11, in progress) | Drills auto-open GLPI tickets with computed DORA/NIS2 deadlines; also a future source for DORA Art. 28's Register of Information via GLPI's asset module |
| Where is evidence parsed? | Nowhere automated — `docs/03-control-matrix.md` is the hand-maintained index into `docs/evidence/samples/` | Phase 14: `make evidence` generates a consolidated report; write-once/tamper-evidence guarantees (build-spec P7) not yet scheduled to a specific phase |
