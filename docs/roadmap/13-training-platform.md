# Track 13: an all-in-one compliance training platform

**Goal:** stand the lab up once, then walk anyone through NIST 800-53, PCI DSS, DORA, NIS2, ISO 27001, and
more. Every control is explained in the terms of its own source framework, tied to the config that implements
it, demonstrated live, and backed by evidence. A teaching tool, not a product. The wording rules in
CONVENTIONS §5 apply to every lens.

## The core design: map frameworks to capabilities, not to each other

Frameworks are never mapped to each other directly. If DORA Art. 9 ≈ ISO A.8.9 and ISO A.8.9 ≈ PCI 2.2, it does
**not** follow that DORA Art. 9 ≈ PCI 2.2. Transitive crosswalks compound errors, and auditors know it.

Instead:

```
framework requirement ──(relationship, basis, rationale)──► capability ◄── implemented_by / evidence / demo
```

- **Capabilities** (`compliance/capabilities/capabilities.yaml`, seeded with 55): things the lab actually does,
  each with implementing files, evidence and a live demo command. One hub.
- **Mappings** (`compliance/mappings/<framework>.yaml`, one per framework): each requirement points at
  capabilities, with:
  - a **relationship**, after NIST OLIR: `equal`, `subset-of`, `superset-of`, `intersects-with`, `supports`;
  - a **basis**: `official` (from a crosswalk published by the framework owner or NIST, cited) or `derived` (this
    repo's judgement);
  - a **rationale** in that framework's own terms.
- **Lenses** are generated from the two: coverage pages, lesson pages, diff reports. Adding framework N costs one
  mapping file.
- `make capabilities-check` validates the whole graph: schema, unique ids, every path exists, every roadmap id is real,
  every mapping cites known capabilities.

**Licensing decides what ships** (`framework.text_licence` in each mapping):

| `open`: requirement text may be quoted briefly | `ids-only`: numbers, permitted titles, and own-words paraphrase |
|---|---|
| NIST (800-53, CSF 2.0, 800-171, SSDF, 800-66), EU law (DORA, NIS2 and its implementing acts, GDPR, CRA), FedRAMP, DISA STIGs, CISA, NSA/CISA guidance, UK NCSC CAF, Australian Essential Eight/ISM | ISO 27001/27002/22301, PCI DSS, CIS Controls and Benchmarks, AICPA SOC 2 criteria, SWIFT CSCF, and CSA CCM (verify its licence) |

Trainers who own licensed texts can load them locally with X14. They never enter Git.

**Order:** X01 → X02, X03 → X04 → the X05 lenses in parallel (X06 before X05p) → X08–X12 → X13 and X14 (optional).

---

## X01 · Complete and review the capability layer

- **Wave / mode:** 8 · offline · **review by a stronger model**
- **Depends on:** none (the seed is on `main` via PR #5)

**Steps:**
1. Read every capability against the repo. Fix wrong statuses and add any missing capability the code
   really implements. Expect about 60–80 in the end. Keep the "one demonstrable thing" granularity:
   "restore measured" and "restored data verified" are separate capabilities because they're evidenced separately.
2. Add a `demo` command to every `implemented` capability, and make it the exact command a trainer types.
3. Move the validator into the test suite (`tests/test_capabilities.py`, calling `compliance/validate.py`) and into the
   `tests` CI workflow.
4. Render `docs/compliance/capabilities.md`, a generated table with family, status, demo command and links. Add it to
   the MkDocs nav.
5. As tracks 01–12 land, each PR that changes a capability's status updates this file. Add that rule to CONVENTIONS §6.

**Done when:** validator and test pass in CI, every `implemented` capability has a demo and either evidence or a stated
reason it has none, and a stronger model has reviewed it.

---

## X02 · Import official crosswalks as a cross-check

- **Wave / mode:** 8 · offline
- **Depends on:** X01

**Why:** `derived` mappings are judgement. Official crosswalks let the repo check that judgement automatically.

**Steps:**
1. `compliance/crosswalks/fetch.py`, pinned by URL and sha256 (same pattern as F05), for the official
   machine-readable crosswalks that exist. Candidates to verify:
   - NIST CSF 2.0 informative references (NIST's CPRT / OLIR);
   - NIST's SP 800-53 Rev 5 ↔ ISO/IEC 27001:2022 mapping;
   - SP 800-171 Rev 3 ↔ 800-53;
   - CIS Controls v8.1 ↔ 800-53 (published by CIS);
   - HIPAA ↔ 800-53 via SP 800-66r2.

   Record the licence of each.
2. `compliance/crosswalks/check.py`: for every pair of frameworks with an official crosswalk, flag pairs of
   requirements that the official crosswalk relates but whose repo mappings share **no** capability, and the reverse.
   It reports. It never auto-edits mappings.
3. Mappings may set `basis: official` only where an imported crosswalk supports them. The check enforces it.

**Done when:** the report is generated in CI as an artifact, and the first run's discrepancies are triaged in the PR.

---

## X03 · Lens generator, with mappings as the single source of truth

- **Wave / mode:** 8 · offline
- **Depends on:** X01, T27

**Steps:**
1. Generalise `docs/compliance/dora_readme.py` into `compliance/lens.py`. For any mapping file it generates:
   - `docs/compliance/<framework>-coverage.csv` and `.md`;
   - a control status **derived** from its capabilities' statuses and the relationship: e.g. `equal` + all implemented
     → Implemented; `supports` never exceeds Partial; any planned capability → at most Partial. Document the rules
     in the page header and test them.
2. Migrate DORA: generate `compliance/mappings/dora.yaml` from `docs/compliance/dora-coverage.csv` (one-off script),
   review every rationale, then make the CSV a **generated output** of the lens generator, so there's one source of
   truth. Keep the README block rendered from the regenerated CSV, and keep `--check` working.
3. Migrate the other existing sheets the same way as they land: the ISO SoA (T15), FedRAMP High (F05), 20x KSIs (F06),
   and baselines (F10a).
4. A framework index page: every lens, its version, licence class, counts by status, and its last review date.

**Done when:** DORA round-trips (the CSV regenerated from YAML matches the reviewed content), the README check passes,
and the status-derivation rules are tested.

---

## X04 · Guided-tour lesson pages

- **Wave / mode:** 8 · offline
- **Depends on:** X03, PR #3 (docs site)

**Steps:**
1. Extend the mapping schema with optional teaching fields: `plain_english`, `why_this_choice` (the design decision,
   argued in the framework's own terms), `auditor_asks` (what an assessor requests), `common_mistakes`.
2. Generate one lesson page per mapped requirement, in a fixed order:
   1. **Source**: quoted (open licence) or paraphrased (ids-only), with a link.
   2. **In plain English.**
   3. **The choice we made, and why**, framed in the source framework.
   4. **The config**: links to and short excerpts of the implementing files.
   5. **See it**: the capability `demo` commands, copy-pasteable.
   6. **The evidence**: links to samples.
   7. **What an auditor asks.**
   8. **Same capability, other frameworks**: every other framework's requirement mapped to the same capabilities.
      This is the multi-framework lesson.
3. One page per capability, listing every requirement in every framework that points at it.
4. Search across lessons (MkDocs Material search is enough).

**Done when:** pages generate for DORA with no hand-written HTML, the strict build passes, and a sample lesson is screenshotted
in the PR.

---

## X05 · Framework lenses (one session each, in parallel once X03 lands)

Each lens = one mapping file + generated pages + the teaching fields for the most important 15–30 requirements +
a short `docs/frameworks/<id>.md` intro: who it applies to, how it's assessed, and how it relates to the others.
Rows are ordered by how cheap they are given the existing lab.

| ID | Framework | Licence class | Notes |
|---|---|---|---|
| X05a | NIST CSF 2.0 | open | Official informative references to 800-53 make it nearly free. A great executive lens |
| X05b | NIST SP 800-171 Rev 3 / CMMC Level 2 | open | Subset of 800-53 Moderate. Check which 800-171 revision CMMC currently cites |
| X05c | GDPR Art. 32 (security of processing) and Art. 33/34 (breach notification) | open | Also add the **72-hour Art. 33 clock** to `drills/lib/clocks.py`, beside DORA and NIS2. The Irish DPC is the audience hook |
| X05d | NIST SSDF (SP 800-218) + SLSA + OpenSSF Scorecard | open | Mostly evidenced already. Add Scorecard in CI as evidence; record the SLSA build level reached |
| X05e | NSA/CISA Kubernetes Hardening Guidance | open | Maps directly onto Kyverno, Cilium, audit logging and RBAC |
| X05f | CIS Controls v8.1 | ids-only | Use CIS's official 800-53 mapping with X02 |
| X05g | CSA Cloud Controls Matrix v4 | verify | Cloud-native; maps to ISO, NIST and PCI |
| X05h | Australian Essential Eight | open | Pairs with the F10d/F10e Windows baselines; teach the maturity levels |
| X05i | CISA Cross-Sector Cybersecurity Performance Goals | open | Small. A "start here" lens |
| X05j | NIS2 Implementing Regulation (EU) 2024/2690 | open | NIS2's concrete technical annex for digital-infrastructure entities |
| X05k | ISO 22301 (business continuity) | ids-only | The drills *are* its exercise programme, so it fits the thesis best |
| X05l | Central Bank of Ireland operational resilience guidance + UK FCA/PRA operational resilience | open (verify) | Impact tolerances map onto measured RTOs. The Dublin/London audience hook |
| X05m | SOC 2 (AICPA Trust Services Criteria) | ids-only | Large market. AICPA publishes mappings to 800-53 and ISO; verify their availability |
| X05n | EU Cyber Resilience Act | open | Manufacturer obligations on SBOM and vulnerability handling. Verify the phase-in dates |
| X05o | HIPAA Security Rule | open | Via NIST SP 800-66r2. Optional tenant X07 makes it concrete |
| X05p | PCI DSS v4.0.1 | ids-only | **Needs X06.** Scoping and segmentation are the lesson |
| X05q | NIST SP 800-53 Rev 5 | open | Migrate from F05's coverage into a mapping file |
| X05r | ISO/IEC 27001:2022 Annex A | ids-only | Migrate from T15's SoA |
| X05s | NIS2 Directive Art. 21/23 | open | Migrate from the existing manifest tags; lex specialis note vs DORA |
| X05t | FedRAMP 20x KSIs / DoD IL5 | open | Migrate from F06/F07 |

**Each lens is done when:** `make capabilities-check` passes, `lens.py` generates its pages, the X02 cross-check report
has no untriaged discrepancies for it, and its intro page is in the nav.

---

## X06 · Payments tenant: a cardholder-data environment (unlocks PCI DSS)

- **Wave / mode:** 9 · offline + live proof
- **Depends on:** tracks 01–02

**Steps:**
1. A small payment-API tenant (own namespace, Wolfi image built and signed like `canary-writer`) that accepts card-shaped
   test data only: **PCI test card numbers, never real ones**, enforced by a Luhn-plus-test-BIN allow-list.
2. Tokenisation: the API stores a token and a truncated PAN. The full PAN goes only to a separate `vault` service holding
   ciphertext under a key from cert-manager or a KMS stand-in. Document key management (PCI Req. 3).
3. Scoping as code: a `cde` namespace label, Cilium policies allowing only the documented flows, and a Kyverno policy
   restricting which images may run in the CDE. Generate a **data-flow diagram** from the Cilium policies. Scoping and
   segmentation are the core PCI lesson.
4. A detector: a Loki alert rule that fires if anything shaped like a PAN appears in any log (PCI Req. 3.3/3.4 and
   10). Add a drill that deliberately logs a test PAN and measures detection.
5. New capabilities (CAP-NET-04 and others), the X05p mapping, and evidence.

**Done when:** the tenant syncs, the segmentation test passes both directions, the PAN-in-logs drill detects, and evidence
is committed.

---

## X07 · Health-records tenant (optional; makes HIPAA concrete)

Same pattern as X06, with synthetic patient records (Synthea-generated, so no real PHI), access logging per record, and
an emergency-access ("break the glass") flow with alerting. Feeds X05o.

---

## X08 · Tabletop exercise engine on real drills

- **Wave / mode:** 9 · offline + live
- **Depends on:** T10, T29, X05c

**Steps:**
1. `exercises/<name>.yaml`: a scenario (which drill to fire) and timed injects. For example, at T+20m: "a journalist
   calls"; at T+3h: "the vendor confirms customer data was exposed". Each inject has decision prompts and the facts that
   are released.
2. `make tabletop EXERCISE=<name>` fires the real drill, runs the inject timeline (terminal plus GLPI ticket updates), and
   records every decision the participants enter with a timestamp.
3. Scoring: classification decisions against `classify.py` with stated reasoning; whether the reports from T29 were
   drafted before each regime's deadline (DORA, NIS2, GDPR); and whether the communication plan (T32) was followed.
4. A debrief report generated from the timeline: what went well, deadlines met or missed, a lessons-learned template
   (DORA Art. 13).

**Done when:** one full exercise runs end to end, and the debrief is generated.

---

## X09 · Mock-audit mode

- **Wave / mode:** 9 · offline
- **Depends on:** X03, X04

`make mock-audit FRAMEWORK=<id> ROLE=<auditor|auditee>`. The auditor mode samples N requirements, weighted towards
high-risk, and issues evidence requests phrased the way that framework's assessor would ask: ISO Stage 2, a FedRAMP 3PAO,
a PCI QSA, a DORA supervisor. The auditee answers with paths to evidence. The tool checks the evidence is real, current,
in the chain, and actually mapped to that requirement, then produces findings (conformity, minor or major non-conformity,
observation) with reasons. This teaches what "evidence" means.

---

## X10 · Break-and-fix labs with automatic grading

- **Wave / mode:** 9 · live
- **Depends on:** X01

`labs/<id>/` each holds: a learning goal tied to requirements in two or more frameworks, a `break.sh` (e.g. remove a
Cilium policy, weaken a Kyverno rule, disable an audit rule), a hint ladder, and a `grade.sh` that uses the capability's
`demo` and verify commands. Students fix the problem **in Git** (the GitOps lesson) and the grader confirms that the
evidence passes again. Start with eight labs across network, admission, logging, backup, PKI, IAM, supply chain and
baselines. `make lab-reset` restores a clean state.

---

## X11 · Framework diff tool

- **Wave / mode:** 9 · offline
- **Depends on:** X03 plus at least three lenses

`make framework-diff FROM=iso27001 TO=dora` generates a report:
- requirements of `TO` already met by capabilities that satisfy `FROM`;
- requirements needing new capabilities;
- requirements that are organisational in `TO` but not in `FROM`.

It works through the capability graph only (no transitive crosswalks) and states that in its header. This answers the
question every multi-framework firm asks: "we're ISO certified, how far are we from DORA?"

---

## X12 · Persona curricula

- **Wave / mode:** 9 · offline
- **Depends on:** X04, X10

Four learning paths with ordered lessons, labs and exercises: **engineer** (configs, labs), **GRC analyst** (mappings,
evidence, mock audit), **auditor** (sampling, evidence quality), and **executive** (lenses, management report, tabletop).
Each has a one-page syllabus with time estimates, prerequisites, and outcomes stated as "can do" statements.

---

## X13 · Grounded tutor (optional)

A chat helper that answers only from the repo's mappings, capability descriptions, lesson pages and cited sources. Every
answer cites the file or source it used, and it refuses when there's no source. It must not answer legal questions beyond
quoting and paraphrasing the cited text. Ship an evaluation set of about 50 question-and-answer pairs and measure citation
accuracy before enabling it.

---

## X14 · Bring-your-own licensed text

- **Wave / mode:** 9 · offline

`make import-licensed FRAMEWORK=pci-dss FILE=<path to the trainer's licensed copy>` parses the trainer's own copy (PDF or
the publisher's spreadsheet) into a **local, gitignored** overlay that X04 lesson pages show in place of the paraphrase
when building locally. CI fails if any overlay file is ever staged. Document the licence terms per publisher.
