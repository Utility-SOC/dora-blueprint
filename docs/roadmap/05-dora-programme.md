# Track 05: the DORA programme, article by article

The [DORA coverage sheet](../compliance/dora-coverage.csv) lists all 64 articles and the main Level 2
acts. Each row has a status, the files that implement it, its evidence, the gap IDs and the task that closes it.
`make dora-coverage` renders it into the README. This track does two things: it verifies the sheet against
the primary text, and it builds the pieces of the *programme* a code repository can sensibly hold. That
means templates and generated documents, not just infrastructure.

Every task here updates the CSV rows it affects and re-renders the README (see CONVENTIONS §6).

**Order:** T27 and T15 in parallel → T32 → (T29, T30 → T31, T33 in parallel).

---

## T27 · Verify and extend the DORA coverage sheet

- **Wave / mode:** 1 · offline · **review by a stronger model**
- **Depends on:** PR #3 merged (its `docs/compliance/dora.md` has quoted, paragraph-level mappings to reconcile with)

**Read first:** `docs/compliance/dora-coverage.csv`, `docs/compliance/dora_readme.py`, PR #3's `docs/compliance/dora.md`
and `gaps.md`, and the DORA text on EUR-Lex (`https://eur-lex.europa.eu/eli/reg/2022/2554/oj/eng`). Record the retrieval
date. If automated retrieval is blocked, use the Official Journal PDF and say so.

**Steps:**
1. **Verify every article title** in the sheet against the Official Journal text and fix any discrepancy. The planning
   pass wrote them from knowledge, not from the text.
2. **Verify every Level 2 row:** instrument number, title, the article it implements, and date of application. Two rows
   are explicitly unverified (the TLPT RTS number, and the status of the subcontracting RTS). Resolve them from EUR-Lex
   or the ESAs' DORA pages. Add any Level 2 instrument that's missing and relevant to the lab, for example the ITS on
   incident reporting forms, the joint guidelines on incident costs and losses (Art. 11(11)), or the RTS on harmonising
   oversight conditions (for teaching only). Each new row needs a status.
3. **Paragraph-level rows for Arts. 5–30 and 45.** For each paragraph or point that imposes a requirement on a financial
   entity, add a row: id `DORA-<art>-<para>`, a short *paraphrase* of the requirement (not a long quote), nature, status,
   how it's addressed, implementing files, evidence, gaps, tasks. Reuse PR #3's mapping where it exists, and agree with it.
   Where the sheet and `dora.md` disagree, fix the wrong one and say which in the PR.
4. **Add a schema and a test** (`tests/test_dora_coverage.py`). It checks:
   - the exact header columns;
   - unique ids;
   - `lab_status` drawn from the fixed vocabulary;
   - all 64 articles present;
   - every path in `implemented_by` and `evidence` exists;
   - every `Partial` or `Not met` row names at least one gap or task;
   - every task id named exists in `docs/roadmap/README.md`'s task table;
   - every gap id exists in `gaps.md`;
   - `dora_readme.py --check` passes.
5. Add `python3 docs/compliance/dora_readme.py --check` to the `tests` CI workflow.
6. Make `docs/compliance/dora.md` point to the CSV as the source of truth for status, so its tables can't contradict it.
   Option: generate its summary table with the same script. The quoted article text stays hand-written.
7. Optional: `make dora-xlsx` writes an `.xlsx` export with one sheet per chapter, filters and frozen header (pinned
   `openpyxl`, output gitignored), for people who live in Excel.

**Done when:** the test passes, the README re-renders, a stronger model has reviewed it against EUR-Lex, and the PR description
lists every title or number that changed.

---

## T15 · Risk register, business impact analysis, and Statement of Applicability

- **Wave / mode:** 1 · offline
- **Depends on:** none (PR #3 merged makes linking easier)

**Why:** `docs/00-scope.md` and `docs/04-limitations.md` link `docs/01-risk-assessment.md` and
`docs/02-statement-of-applicability.md`, which don't exist (gap G14). DORA Art. 6 and 8, Art. 11(5) (BIA) and ISO 27001
Clause 6 all start here. An auditor asks for these first.

**Files:** new `docs/01-risk-assessment.md`, `docs/01-risk-register.csv`, `docs/02-statement-of-applicability.md`, and
`docs/02-soa.csv`, plus a small renderer (reuse `dora_readme.py`'s approach or generalise it into
`docs/compliance/render_sheet.py`).

**Steps:**
1. **Business impact analysis** for the notional tenant "Meridian Pay" (`docs/00-scope.md`). List 4–6 business functions
   (e.g. card payment authorisation, customer onboarding, settlement file exchange, customer support). For each: critical
   or important (DORA definition), maximum tolerable downtime, RTO, RPO, dependencies on this platform's components, and
   the drill that tests it. Label every number as a *synthetic assumption* and show how the drill targets derive from it.
2. **Risk register** (`01-risk-register.csv`), 12–20 ICT risks. Columns: id, risk, asset or function, threat, vulnerability,
   likelihood (1–5), impact (1–5), inherent score, treatment (mitigate/accept/transfer/avoid), controls (links to files),
   evidence (links to samples), residual likelihood, residual impact, residual score, owner role (from the three-operator
   model), review date, and related DORA, ISO and NIST ids. Include risks the lab *doesn't* treat (e.g. a regional cloud
   outage, insider with cluster-admin, loss of the only operator) and mark them as accepted or untreated, honestly.
3. `01-risk-assessment.md` explains the method: scales, appetite statement (synthetic), how the register is reviewed, and
   how drills feed residual-risk scoring. It renders a summary table from the CSV.
4. **Statement of Applicability** (`02-soa.csv`): all 93 ISO/IEC 27001:2022 Annex A controls, by **number and title only**
   (the text is copyrighted). Columns: control, title, applicable (yes/no), justification, implementation status
   (Implemented/Partial/Not met/Not applicable), implemented by (files), evidence, and the related DORA articles. Most
   A.5 (organisational) and A.6 (people) controls will be "applicable, not met, organisational", and that's correct.
   A.7 (physical) is "not applicable: cloud-hosted, inherited from provider", per the NIST PE reasoning already in
   `docs/06-nist-800-53-crosswalk.md`.
5. Add both pages to the MkDocs nav and the README Docs list. Close G14. Update the DORA sheet rows for 6(1), 8 and 11(5).

**Tests:** the CSV schemas (columns, vocabularies, scores in 1–25, every path exists), 93 SoA rows, unique control ids
matching `A\.(5|6|7|8)\.\d+`, and each risk's residual score ≤ its inherent score unless the risk is accepted.

**Done when:** tests pass, the links that pointed at missing files now resolve, and the docs site builds strictly.

---

## T32 · DORA governance pack, plus a generated management report

- **Wave / mode:** 1 (after T15) · offline
- **Depends on:** T15

**Covers:** Art. 4 (proportionality, quantified), Art. 5 (management body), Art. 6(8) (digital operational resilience
strategy), Art. 11(1) (ICT business continuity policy), Art. 13 (post-incident review), Art. 14 (communication),
Art. 17(3)(c) and (e) (roles; reporting to senior management), and Art. 28(2) (third-party strategy, cross-linked to T31).

**Files:** new `docs/dora/` with:
- `strategy.md`: digital operational resilience strategy (template, partially filled for Meridian Pay);
- `bcp-policy.md`: ICT business continuity policy, linked to the BIA from T15 and the drills;
- `crisis-communication-plan.md` (Art. 14): internal escalation, client communication, and media and authority contact
  points, with templates for each message;
- `roles-raci.md`: a RACI for the three-operator model plus the management body, for every DORA process
  (risk, incidents, testing, third parties);
- `post-incident-review.md`: a template replacing the GLPI boilerplate (G24), with a section a human must complete; the
  ticket links to it and flags "review incomplete" until done;
- `proportionality.md`: Art. 4 reasoning, quantified with the BIA's numbers.

**The technical hook, so it's not just paperwork:** `docs/dora/management_report.py` generates
`docs/dora/management-report-<yyyy-mm>.md` from real data:
- drills run that month, with verdicts and the RTO/RPO trend (from the evidence samples and, once T11 runs, Loki
  exports);
- incidents opened, by classification;
- notification deadlines met or missed (computed);
- open gaps from `gaps.md`, with their age;
- coverage-sheet counts by status;
- top residual risks from the risk register.

This is the Art. 5 and 17(3)(e) "management body is informed" artifact, generated rather than written.

**Steps:**
1. Every template opens with a banner: "TEMPLATE for a notional entity, not an adopted policy." Bracket the
   organisation-specific choices. Wherever the lab implements a policy statement, put a "→ implemented by" link right
   next to it.
2. Build the report generator with tests (fixture evidence → expected Markdown). Add a `make management-report` target.
3. Update the DORA sheet rows for 4, 5, 5(2), 6(8), 11(1), 13, 14, 17(3)(c), 17(3)(e) and 28(2). Most move from
   "Not met" to "Partial: template + generated report; adoption is organisational". Close G24 if the review flow is wired.

**Done when:** templates and generator are merged, tests pass, and one generated report from the existing samples is
committed as an example.

---

## T29 · Incident report drafts in the official template structure

- **Wave / mode:** 2 · offline · **review by a stronger model**
- **Depends on:** T10

**Covers:** Art. 19 (reporting), Art. 20 (harmonised templates), Art. 19(3) (informing clients), Art. 17(3)(e)
(senior-management reporting), and Art. 23 (payment-related incidents, for the notional payment institution).

**Read first:** Commission Implementing Regulation (EU) **2025/302** (standard forms and templates for incident reporting;
verify the number and fetch the annex) and Delegated Regulation (EU) **2025/301** (report content). List the
data fields of the initial, intermediate and final reports from the annex.

**Steps:**
1. `drills/lib/report_drafts.py`: from an enriched drill record, produce three draft reports (initial, intermediate, final)
   as JSON shaped like the template's data fields, plus Markdown renderings. Fill the fields the lab can measure
   (timestamps, duration, data loss, classification criteria tripped, affected services) from the record. Fill the
   synthetic profile fields and **label them synthetic**. Leave the rest as explicit `null` with a reason. Never invent values.
2. Field-mapping table `docs/compliance/incident-report-fields.csv`: template field → source (`measured`, `synthetic`,
   `manual`) → record field. Render it in the docs site. This table is the teaching artifact: it shows how much of a regulatory
   report a platform can fill automatically.
3. Also generate a client-notice draft (Art. 19(3)) and a short senior-management summary (17(3)(e)) from the same record.
4. Attach the drafts to the GLPI ticket (as a follow-up note, or as document attachments if the GLPI API allows it). Add
   them to the drill's output in `run-drill.sh`, or in the workflow step after T11.
5. Every draft carries a banner: "DRAFT generated from a lab drill. Not submitted. Not a regulatory filing."
6. Update the DORA sheet rows for 19, 19(3), 20, 23, 17(3)(e) and `L2-ITS-REPORT`.

**Tests:** fixtures for a major and a non-major record; JSON field coverage against the mapping CSV; no field marked
`measured` is ever filled from synthetic input.

**Done when:** tests pass, the mapping table is published, and the legal reading has been reviewed by a stronger model.

---

## T30 · Register of Information in the ITS structure, plus concentration analysis

- **Wave / mode:** 2 · offline
- **Depends on:** none (better after T27 verifies the ITS number)

**Covers:** Art. 28(3) (register), Art. 29 (concentration risk), Art. 8 (identification), and ITS (EU) 2024/2956 (verify).

**Read first:** `images/generate-roi.py` and its tests; the ITS annex (templates and their columns; verify the template
codes, e.g. `B_01.01`, from the text, not from memory); and the EBA/ESA reporting guidance on the register (data
point model), for orientation only.

**Steps:**
1. Restructure the generator's output into the ITS template tables, one CSV per template, under
   `docs/compliance/register-of-information/`. Keep the existing Markdown view as a human summary.
   - Fill the inventory facts the repo knows (provider or project, component, version, digest, function supported, criticality).
   - Contract, legal entity identifier and financial fields are synthetic and labelled synthetic.
   - Columns that can't be filled stay empty and are listed in a README.
2. **Concentration analysis** (`docs/compliance/concentration-risk.md`, generated): group dependencies by upstream
   provider and supply route. For example: images from Docker Hub vs GHCR vs quay.io; charts from Bitnami vs project
   repositories; GitHub as the single source for GitOps, CI and the registry. Then show:
   - single points of failure (e.g. GitHub down means no GitOps sync and no image builds);
   - substitutability (link the alternatives from F01 once they exist);
   - which critical functions from T15's BIA each dependency touches.

   Include the real current case of **MinIO community edition being frozen (G17)** as a worked example.
3. Update the DORA sheet rows for 8, 28(3), 29 and `L2-ITS-ROI`.

**Tests:** every Application and image in `apps/` and `infrastructure/` appears in the register; template CSV headers
match the ITS column list (hard-coded from the verified annex, with a source comment); the concentration report is
deterministic.

**Done when:** tests pass and both outputs are linked from the docs site.

---

## T31 · Third-party strategy, contract checklist and exit plans

- **Wave / mode:** 2 · offline
- **Depends on:** T30

**Covers:** Art. 28(2) (strategy), 28(4) (pre-contract assessment), 28(8) (exit strategies), Art. 30 (key contractual
provisions), RTS (EU) 2024/1773 (policy on ICT services supporting critical or important functions), and the
subcontracting RTS (verify its status).

**Files:** `docs/dora/third-party/` containing:
- `strategy.md`: template;
- `pre-contract-assessment.md`: template plus a filled example for one real upstream, e.g. Grafana Labs (Loki/Grafana);
- `contract-checklist.yaml`: one entry per Art. 30(2) and 30(3) provision (verify the list against the text), each with an
  id, a paraphrase, and whether it applies to all ICT services or only those supporting critical or important functions;
- `providers/<provider>.yaml`: per provider in the register, the checklist status (`n/a: open source, self-hosted` is a
  legitimate value, and teaching *why* it's different from a SaaS contract is the point);
- `exit-plans/minio.md`: a **real** worked exit plan from frozen MinIO CE to a maintained S3-compatible store, listing the
  candidates (link F01), the migration steps, a test plan, and how a drill would prove the exit works.

**Steps:** write the templates, the checklist schema and test, and the generator that joins the checklist with the register
into a status table. Update the DORA sheet rows for 28, 28(2), 28(8), 30, `L2-RTS-TPPOL` and `L2-RTS-SUBCON`.

**Done when:** the checklist validates, the status table is generated, and the MinIO exit plan is complete enough that
someone could run it.

---

## T33 · Threat-intelligence sharing export (STIX 2.1)

- **Wave / mode:** 2 · offline · optional
- **Depends on:** none

**Covers:** Art. 45 (information-sharing arrangements), as a teaching example.

**Steps:**
1. `docs/evidence/stix_export.py` builds a STIX 2.1 bundle from the lab's own material. Use the pinned `stix2` library and
   validate with `stix2-validator`.
   - `attack-pattern` objects for T1485 and T1059.004, referencing MITRE ATT&CK external ids;
   - an `indicator` per Grafana detection rule (a pattern describing the observable, honestly scoped);
   - a `sighting` per drill detection, with the measured `t_detect`;
   - a TLP marking (TLP:CLEAR for the lab; explain the TLP levels);
   - an `identity` for the notional entity.
2. A teaching doc, `docs/dora/information-sharing.md`: what Art. 45 permits and requires (arrangements within trusted
   communities, notifying authorities of participation, data protection), the communities firms use (e.g. FS-ISAC,
   national CSIRT channels; verify the Irish options), MISP/TAXII as transports, and what a firm must strip before sharing.
3. Update the DORA sheet row 45 to "Partial: export mechanism demonstrated; no sharing arrangement."

**Tests:** the bundle validates, is deterministic for fixed inputs, and contains no internal hostnames or secrets.

**Done when:** tests pass and the doc is in the nav.
