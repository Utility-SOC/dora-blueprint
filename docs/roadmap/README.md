# Roadmap: building dora-blueprint out, one agent session at a time

This directory is the build plan for everything still ahead: the cloud-hosted demo, the
article-by-article DORA programme, and the teaching build-out (ISO 27001, FedRAMP 20x High / DoD
IL5, hardening baselines, alternatives, and cloud equivalents).

It is written to be **handed to a coding agent one task at a time.** Sonnet is the default. A
stronger model is used only to *review* the few tasks marked for it. Every task is sized for one
session and has its own spec, with files, steps, tests and "done when".

**What this project is:** a teaching reference architecture. It shows the *architecture and bones*
of a resilience and security programme, and explains how a real firm would grow them into one.
**What it is not:** a product, a certification, or a claim that anyone running it is compliant
with DORA, ISO 27001, FedRAMP, or IL5. No audit, no assessor, no operating history.

## Start here

1. Read [`CONVENTIONS.md`](CONVENTIONS.md). Every session follows it.
2. Make the owner decisions below. Some tasks are blocked on them.
3. Hand out tasks wave by wave using the prompt in [Handing a task to an agent](#handing-a-task-to-an-agent).

## Where things stand (2026-10-06)

- **On `main`:** Talos + Cilium + Argo CD GitOps platform; five measured drills
  (ns-restore, node-kill, pvc-corruption-restore, network-partition, credential-compromise);
  DORA Art. 18 classification and Art. 19 / NIS2 Art. 23 clocks; GLPI tickets; Tetragon detection;
  Trivy + CISA KEV; signed images with SBOMs; generated Register of Information; hash-chained evidence
  with a keyless-signed chain head; OSCAL export; NIST 800-53 and ATT&CK crosswalks; and the
  [DORA coverage sheet](../compliance/dora-coverage.csv), rendered into the README.
- **Open, unmerged PRs:** [#1](https://github.com/Utility-SOC/dora-blueprint/pull/1) (re-keyed secrets and low-memory
  bootstrap knobs), [#2](https://github.com/Utility-SOC/dora-blueprint/pull/2) (345 offline tests and CI),
  [#3](https://github.com/Utility-SOC/dora-blueprint/pull/3) (docs site, article-level compliance pages, gaps
  register G1–G24), and [#4](https://github.com/Utility-SOC/dora-blueprint/pull/4) (cloud-VM host prep). They merge cleanly together.
- **Not working yet on a cloud host:** a home-LAN address is hard-coded in about 55 files, the public
  CA certs drifted from the re-issued CA, the `canary-writer` image can't be pulled, the API tokens are
  placeholders, and nothing has booted since the re-key.
- **Claims not yet true:** drills aren't scheduled, verdicts ignore RTO/RPO targets, and one sample
  has a negative RPO.

## Owner decisions

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| D1 | Merge PRs #1–#4 | Yes: #1, then #2 → #3 → #4, updating each next PR's base to `main` | everything |
| D2 | Cloud provider | Hetzner CCX33 (dedicated, ~€0.22/h) to rehearse; AWS eu-west-1 or Azure North Europe (Dublin) for the talk if the story matters. Destroy between sessions | T08, wave 3 |
| D3 | Reaching the UIs | Tailscale on the VM and laptop. No public ports | T03–T05 |
| D4 | `canary-writer` package visibility | Public (it is signed and SBOM-attested) | T06 |
| D5 | Make the repo public | Yes, after T23. It also lets Argo CD read Git with no credential | T02b, T22, T25 |
| D6 | ~~Age key on a VM~~ | Resolved: every stand-up generates its own secrets (T02a–c) | — |
| D7 | Who operates the VM | Install Claude Code on the VM so an agent can run the live tasks | wave 3 |
| D8 | Branch protection on `main` | Require the `tests` and `docs` checks and one review (DORA Art. 9(4)(e), gap G9) | — |

### Merge note for D1: add the roadmap to the docs-site nav

PR #3's `tests/test_docs_site.py::test_every_page_is_in_the_nav` requires every Markdown page under `docs/`
to appear in `mkdocs.yml`'s nav. Whichever lands second (PR #3 or the branch adding `docs/roadmap/`) must add this
block to the nav, or that test goes red:

```yaml
  - Roadmap:
      - Overview: roadmap/README.md
      - Conventions: roadmap/CONVENTIONS.md
      - 01 Secrets and PKI: roadmap/01-secrets-pki.md
      - 02 Cloud hosting: roadmap/02-cloud-hosting.md
      - 03 CI and supply chain: roadmap/03-ci-supply-chain.md
      - 04 Claims made true: roadmap/04-claims.md
      - 05 DORA programme: roadmap/05-dora-programme.md
      - 06 Showcase: roadmap/06-showcase.md
      - 07 Live bring-up: roadmap/07-live.md
      - 08 Alternatives and cloud: roadmap/08-alternatives-cloud.md
      - 09 ISO 27001: roadmap/09-iso27001.md
      - 10 FedRAMP 20x / IL5: roadmap/10-fedramp-il5.md
      - 11 Hardening baselines: roadmap/11-baselines.md
      - 12 Capstone: roadmap/12-capstone.md
      - Demo script: roadmap/demo-script.md
```

Also add `compliance/*.csv` and `compliance/*.py` to `exclude_docs` (they are data and code, not pages), and link
`compliance/dora-coverage.csv` from `compliance/index.md`.

## Waves

Tasks in the same wave touch different files and can run in **parallel sessions**. Within a track,
run tasks in order. Merge each PR before starting a task that depends on it.

| Wave | Track file | Tasks, in order | Mode |
|---|---|---|---|
| 0 | (owner) | D1–D5, D7, D8 | — |
| 1 | [01 Secrets and PKI](01-secrets-pki.md) | T02a → T02b → T02c | offline |
| 1 | [03 CI and supply chain](03-ci-supply-chain.md) | T07 | offline |
| 1 | [04 Claims made true](04-claims.md) | T09 → T10 → T12 → T11 | offline + live proof |
| 1 | [05 DORA programme](05-dora-programme.md) | T27, T15 (parallel), then T32 | offline |
| 2 | [02 Cloud hosting](02-cloud-hosting.md) | T03 → T04 → T05 → T06 → T08 | offline |
| 2 | [03 CI and supply chain](03-ci-supply-chain.md) | T25 (after T02b, T03) | CI |
| 2 | [05 DORA programme](05-dora-programme.md) | T29, T30 → T31, T33 | offline |
| 2 | [06 Showcase](06-showcase.md) | T16, T13, T14, T24 | offline |
| 3 | [07 Live](07-live.md) | T17 → T18 → T19 → T20 → T21 | live |
| 4 | [06 Showcase](06-showcase.md) | T23 → T22, then T26 (owner) | offline / owner |
| 5 | [08 Alternatives and cloud](08-alternatives-cloud.md) | F01a, F01b, F01c, F01d (parallel), then F02 | offline |
| 5 | [09 ISO 27001](09-iso27001.md) | F03 → F04 | offline |
| 6 | [10 FedRAMP 20x / IL5](10-fedramp-il5.md) | F05 → F06 → F07 | offline |
| 6 | [11 Hardening baselines](11-baselines.md) | F10a → F10b, F10c, F10d, F10e (parallel) → F10f → F10g | offline + CI |
| 7 | [12 Capstone](12-capstone.md) | F08 → F09 | live, then offline |

**Waves 0–4 deliver the demo**, about 25 sessions plus a few days of live bring-up. **Waves 5–7
deliver the teaching build-out**, about 25–30 sessions. Without a VM, everything except wave 3 and
F08 can proceed.

## All tasks

| ID | Title | Track | Needs live cluster | Review by stronger model |
|---|---|---|---|---|
| T02a | Generate the PKI in-cluster with cert-manager | 01 | proof only | **yes** |
| T02b | Generate every credential at bootstrap | 01 | proof only | **yes** |
| T02c | Remove SOPS plumbing; teach the production pattern | 01 | no | |
| T03 | One configurable access host instead of `192.168.1.106` | 02 | proof only | |
| T04 | Host-agnostic port-forward units | 02 | proof only | |
| T05 | Tailscale in host prep | 02 | no | |
| T06 | Fix `canary-writer` image pull | 02 | no | |
| T08 | One-command VM provisioning (cloud-init) | 02 | no | |
| T07 | Pin CI tooling by version and SHA | 03 | no | |
| T25 | CI smoke bring-up of the `core` tier | 03 | runs in CI | |
| T09 | Drill verdict honours RTO/RPO targets | 04 | proof only | |
| T10 | Intermediate and final reporting deadlines | 04 | no | **yes** |
| T11 | Schedule the drills; alert on missed runs | 04 | proof only | |
| T12 | Find and fix the negative-RPO bug | 04 | proof only | |
| T15 | Risk register, BIA and Statement of Applicability | 05 | no | |
| T27 | Verify and extend the DORA coverage sheet | 05 | no | **yes** |
| T29 | Incident report drafts in the official template structure | 05 | no | **yes** |
| T30 | Register of Information in ITS structure + concentration analysis | 05 | no | |
| T31 | Third-party strategy, contract checklist and exit plans | 05 | no | |
| T32 | DORA governance pack + generated management report | 05 | no | |
| T33 | Threat-intel sharing export (STIX 2.1) | 05 | no | |
| T13 | Alert notifications to a real channel | 06 | proof only | |
| T14 | MFA for operators | 06 | proof only | |
| T16 | README: demo-first front page, stale claims | 06 | no | |
| T22 | Publish the docs site | 06 | no | |
| T23 | Public-readiness audit | 06 | no | |
| T24 | Interactive "anatomy of an incident" page | 06 | no | |
| T26 | Rehearse the demo twice | 06 | yes (owner) | |
| T17 | First cloud bring-up | 07 | **yes** | |
| T18 | Prove the generated API tokens end to end | 07 | **yes** | |
| T19 | Fresh evidence on current code | 07 | **yes** | |
| T20 | Screenshots and recordings | 07 | **yes** | |
| T21 | Teardown, snapshot, cost guard | 07 | **yes** | |
| F01a–d | Alternatives and cloud equivalents on every component page | 08 | no | |
| F02 | AWS / Azure / GCP reference architectures | 08 | no | |
| F03 | ISO 27001: from bones to an ISMS | 09 | no | |
| F04 | ISMS policy templates linked to enforcing controls | 09 | no | |
| F05 | Generated FedRAMP High baseline coverage | 10 | no | **yes** |
| F06 | FedRAMP 20x Key Security Indicators mapped to evidence | 10 | no | **yes** |
| F07 | DoD IL5 explainer | 10 | no | **yes** |
| F10a–g | Hardening baselines: Linux, Windows, verify scripts, drift | 11 | CI only | |
| F08 | Hardening and crypto evidence on the live cluster | 12 | **yes** | |
| F09 | "Use these bones to build your programme" capstone | 12 | no | |

Task numbers are stable identifiers, not an order. Gaps in the sequence (T01, T28) are retired IDs.
An earlier single-file draft of this plan is in git history; these files supersede it.

## Handing a task to an agent

Paste this, filling in the task ID:

```text
You are working in the dora-blueprint repository. Before anything else, read
docs/roadmap/CONVENTIONS.md and BUILD-SPEC.md §1 (principles P1–P8).

Your task is <TASK ID> in docs/roadmap/<TRACK FILE>. Do only that task. Read the whole
task spec, including "Read first" and "Out of scope", before changing anything.

Follow CONVENTIONS.md exactly: new branch off main, tests before every push, CHANGELOG
entry, PR against main whose description ticks off each "Done when" item with how you
verified it. If the task has live steps and you have no cluster, finish the offline part
and list the exact commands the owner must run. If you find a problem outside the task,
record it in the PR description; do not fix it.
```

To have a stronger model review the PR, use: *"Review PR #N against task <ID> in
docs/roadmap/<file> and CONVENTIONS.md. Check every factual claim about regulation text against the
primary source. Report problems; do not rewrite the PR."*

## Other files here

- [`demo-script.md`](demo-script.md) is the 25-minute talk track for Dublin financial-sector audiences.
