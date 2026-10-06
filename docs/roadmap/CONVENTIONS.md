# Conventions for every task

Read this before starting any task in `docs/roadmap/`. It holds the rules that apply everywhere,
so the task specs don't repeat them. Where a task spec says otherwise, the task spec wins.

## 1. The project's principles still apply

`BUILD-SPEC.md` §1 is binding. In short:

- **P1, no claim without an implementation.** Every sentence that says the lab *does* something
  links to the file that does it, and ideally to generated evidence. If you can't link it, write
  "planned" or delete the claim.
- **P2, explicit exceptions.** A privileged workload or a baseline deviation gets a committed exception
  file with a reason, an owner role, a compensating control and an expiry, in the same commit.
- **P3, pin everything.** Chart versions, image digests, GitHub Actions by commit SHA, tool releases by
  version and checksum. Never `latest`, `stable`, `HEAD`, or a floating tag.
- **P4, GitOps.** Workloads arrive through Argo CD. `bootstrap/install.sh` is the only imperative step.
- **P5, no secrets in Git** (as revised by T02c). Credentials are generated at stand-up and live only in
  the cluster. Tokens a user supplies come in through environment variables and are never written to disk
  inside the repo.
- **P6, measured, not asserted.** Numbers come from probes and tools, never from a value someone typed.
- **P8, limitations are stated.** When the lab can't do something, add it to `docs/04-limitations.md`
  or the gaps register. Don't fake it.

## 2. Git workflow

- Branch off the latest `main`: `git fetch origin main && git checkout -b <prefix>/<task-id>-<short-name> origin/main`.
  Prefixes: `feat/`, `fix/`, `docs/`, `ci/`, `test/`.
- Small, focused commits with messages that say *why*. One task per PR.
- Don't rewrite shared history. Don't push to `main` directly.
- Open the PR against `main`. Its description has three parts:
  1. **What and why**, two or three sentences.
  2. **Done when**: copy each criterion from the task spec as a checkbox, each with how you verified it
     (a command and its result).
  3. **Found but not fixed**: anything broken outside the task's scope.
- If you depend on an unmerged PR, say so at the top and base your branch on it. Prefer waiting for the merge.

## 3. Before every push

Once PR #2 is merged, the offline test suite exists. Run, at minimum:

```bash
python3 -m pytest -q                         # whole offline suite
make evidence-verify                         # evidence hash chain intact
python3 docs/compliance/dora_readme.py --check   # README DORA section matches the CSV
mkdocs build --strict                        # only if you touched docs/ and PR #3 is merged
```

Then re-read your own diff and ask: what would make CI or a reviewer reject this? Fix that first.
Add tests for the behaviour you add. A test that only proves the file exists isn't enough.

## 4. Evidence rules

- `docs/evidence/samples/` is **append-only**. Never edit or delete a sample. A bad sample is annotated
  in docs, not rewritten.
- After adding samples, tag them in `docs/evidence/manifest.yaml` and run `make evidence`. Commit the
  regenerated `integrity-chain.json`, `oscal-assessment-results.json`, `report.md` and `by-control/`.
  The chain grows; history doesn't change.
- Name samples `<topic>-<UTC yyyymmddHHMMSS>.<ext>`. Record the git SHA and the command that produced them
  inside the file where the format allows.

## 5. Regulatory and standards content

- **Use primary sources** and cite them with a URL and the retrieval date: EUR-Lex for DORA, NIS2 and the
  delegated and implementing acts; NIST for SP 800-53 and its OSCAL content; fedramp.gov and FedRAMP's GitHub
  organisation for FedRAMP and 20x; DISA for the Cloud Computing SRG and STIGs; the Central Bank of Ireland
  for Irish supervisory material.
- If a primary source can't be fetched, say so. Don't fill the gap from memory. Mark the claim "to verify".
- **Copyright:** ISO/IEC 27001 and CIS Benchmark text are licensed. Use control *numbers and titles* only.
  EU legislation and US government publications may be quoted, but keep quotes short and attributed.
- **Wording rules.** Never write that this repo, or anyone running it, *is compliant*, *is certified* or
  *is authorized*. Use "maps to", "demonstrates the mechanism for", "contributes evidence toward", and
  "not met". Status words in sheets and tables are fixed: **Implemented** (a mechanism exists *and*
  produced evidence), **Partial**, **Not met**, **Not applicable**, **Out of scope**, **Context**.
- Synthetic inputs (client counts, contract fields, economic impact) are labelled synthetic where they
  are defined *and* where they're displayed.

## 6. Coverage sheets are the source of truth

- DORA: [`docs/compliance/dora-coverage.csv`](../compliance/dora-coverage.csv). The README section is
  generated from it with `make dora-coverage`. Never hand-edit the generated block.
- When your task changes the status of a DORA requirement, update its CSV row(s) (`lab_status`,
  `how_addressed`, `implemented_by`, `evidence`, `gaps`, `tasks`) and re-render the README in the same PR.
- Later tasks add sibling sheets in the same shape: ISO 27001 SoA (T15), FedRAMP High coverage (F05),
  20x KSIs (F06), baseline mappings (F10a). Keep the column names consistent so one script can read them all.
- The **capability layer** (`compliance/capabilities/capabilities.yaml`) is the hub every framework maps to
  (track 13). When your task changes what the lab can do, update the capability's `status`, `implemented_by`,
  `evidence` or `demo` in the same PR, and run `make capabilities-check`.
- When a gap closes, update `docs/compliance/gaps.md` (once PR #3 is merged) with a link to the PR and evidence.

## 7. Live steps

Tasks marked *live* or *proof only* need a running cluster. If you have one (Claude Code on the demo
VM), run the steps and capture output as evidence. If you don't:

1. Finish and test everything offline.
2. In the PR description, add a **Live verification** section with the exact commands, the expected
   output, and what to do if it differs.
3. Leave the corresponding gap status as "fixed, pending live verification".

Never hot-patch a live cluster with `kubectl edit` or `apply` to make something work. Fix it in Git
and let Argo CD sync it. Record every live-found bug in CHANGELOG under a "caught live" note, as earlier
phases did.

## 8. CHANGELOG

Add an entry at the **end** of `CHANGELOG.md` (it is ordered oldest first) under a heading naming the task ID. Say what changed, why, what
was verified and how, and anything found along the way. Match the existing entries' tone: specific,
honest, including what didn't work.

## 9. Definition of done (all tasks)

- [ ] Every "Done when" item in the task spec is met and evidenced in the PR description.
- [ ] Tests added or updated, and the whole suite passes.
- [ ] `make evidence-verify` passes, and the DORA README check passes.
- [ ] Coverage sheet rows and the gaps register are updated where the task changes a status.
- [ ] Docs updated wherever behaviour changed, including the MkDocs nav if you added a page.
- [ ] CHANGELOG entry.
- [ ] Nothing pinned to a floating version. No secret material committed.
