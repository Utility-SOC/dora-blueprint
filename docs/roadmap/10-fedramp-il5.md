# Track 10: FedRAMP 20x at the High baseline, and DoD Impact Level 5

**Owner direction:** show the *architecture and bones* for FedRAMP 20x High and DoD IL5, and explain how a
real programme would grow from them. This is a teaching tool. It cannot achieve either: no third-party
assessment organisation (3PAO), no agency or DoD authorising official, no FedRAMP Marketplace listing, no
continuous-monitoring history, no cleared personnel, no government-only infrastructure. Every page says so
in its first paragraph.

**Why 20x fits this repo:** FedRAMP 20x moves away from narrative-heavy authorisation packages toward
**automated, machine-readable validation** of Key Security Indicators (KSIs). That is this repo's own
thesis, "measured, not asserted." The generated evidence pipeline (manifest → per-control folders → OSCAL →
signed chain head) is the mechanism 20x asks for.

**Sources.** Primary only. Record the version and retrieval date of each:
- NIST SP 800-53 Rev 5 OSCAL catalog: NIST's `oscal-content` repository.
- FedRAMP Rev 5 High baseline OSCAL profile: GSA's `fedramp-automation` repository (verify the current location;
  FedRAMP has been reorganising its repos).
- FedRAMP 20x: fedramp.gov and FedRAMP's GitHub organisation. Use the current KSI release, and **check which baselines
  20x covers at the time you work.** It began as a Low pilot in 2025 and expanded in phases. Anything about 20x *at High*
  that isn't published yet is marked "not yet published", never inferred.
- DoD Cloud Computing Security Requirements Guide (CC SRG): DISA's public site. Note its version.

**Wording:** "maps to", "would contribute evidence toward", "not met". Never "FedRAMP ready", "IL5 compliant" or "authorized".

**Order:** F05 → F06 → F07. F06 and F07 can overlap once F05 has landed.

---

## F05 · Generated FedRAMP High baseline coverage

- **Wave / mode:** 6 · offline · **review by a stronger model** (the classification calls)
- **Depends on:** PR #3 merged; T15 helps

**Files:** `compliance/baselines/fetch.py` plus `compliance/baselines/sources.yaml`, which records each source's URL,
pinned commit SHA and sha256. Also `compliance/fedramp-high/classification.yaml`, `compliance/fedramp-high/coverage.py`,
and the outputs `docs/compliance/fedramp-high-coverage.md` and `.csv`. Tests in `tests/test_fedramp_coverage.py`.

**Steps:**
1. `fetch.py` downloads the pinned OSCAL catalog and the High profile **by commit SHA**, verifies their sha256, and caches
   them in a gitignored directory. CI fetches them too, so the large JSON isn't committed.
2. Resolve the profile against the catalog (the controls and enhancements in the High baseline, with FedRAMP parameter
   values). A small, documented resolver for the `imports` and `include-controls` shapes the profile actually uses is fine.
   Note any profile features you don't support.
3. `classification.yaml` is small and hand-maintained, keyed by **control family or control id**. It assigns:
   - `implemented` (a mechanism plus evidence; it must cite manifest evidence);
   - `partial`;
   - `inherited` (from the cloud provider: e.g. most of PE, parts of MA and MP, per the existing reasoning in
     `docs/06-nist-800-53-crosswalk.md`);
   - `organisational` (policy and people: most of AT, PL, PS, PM, much of CA);
   - `not-addressed`.

   Family-level defaults keep it short, and per-control overrides capture the specifics. Join the result with the
   `nist80053:*` tags in `docs/evidence/manifest.yaml`: any control with tagged evidence is a candidate for
   implemented or partial.
4. Generate the coverage page and CSV, with counts per class at the top. Expect most of roughly 400 controls to be
   organisational or not-addressed. Say so in the first paragraph: honesty is the lesson. Add per-family tables and the
   parameter values for implemented controls where they matter (e.g. AU retention).
5. Update `docs/06-nist-800-53-crosswalk.md` to say it's the hand-written, representative subset, with the full generated
   view in the coverage page.

**Tests:** fetch verification (a bad checksum fails); profile resolution on a tiny fixture profile; the generator is
deterministic (run twice, diff); every `implemented` row cites evidence that exists.

**Done when:** tests pass, the page is in the nav, and the classification has been reviewed by a stronger model.

---

## F06 · FedRAMP 20x: Key Security Indicators mapped to real evidence

- **Wave / mode:** 6 · offline · **review by a stronger model**
- **Depends on:** F05

**Files:** `compliance/fedramp-20x/ksi.yaml` (pinned KSI release, with source and version), a `ksi` tag family in
`docs/evidence/manifest.yaml` and `collect.py`, `docs/compliance/fedramp-20x.md`, and tests.

**Steps:**
1. Import the current published KSI list: themes, ids, statements, and any related 800-53 controls FedRAMP lists. Pin
   it by version and retrieval date. Don't paraphrase KSI ids or invent new ones.
2. For each KSI, record a validation type:
   - `automated`: a script, drill, policy or CI job produces a generated artifact. Name it.
   - `manual`: a human produces evidence, and this repo holds the template.
   - `none`.

   Record the validation's frequency too: per commit, scheduled, or per drill. 20x emphasises continuous validation, so
   T11's scheduled drills and F10g's drift checks are the strongest answers.
3. Tag existing evidence with KSI ids so `collect.py` generates `docs/evidence/by-control/ksi/…`, the same way it does
   for the other five frameworks. Regenerate with `make evidence`.
4. `fedramp-20x.md` explains:
   - what 20x changes compared with Rev 5 packages, and why;
   - the KSI table with this repo's validation per KSI;
   - which KSIs need a cloud service provider's organisation and can't be met by architecture;
   - and, clearly labelled, **what is and isn't published for High** at the time of writing.
5. Stretch: if FedRAMP has published a machine-readable format for 20x validation results, emit it from the manifest,
   next to the OSCAL export. If it hasn't, write that down, and **don't invent a format.**

**Tests:** every KSI in `ksi.yaml` has a row; every `automated` row names a file or workflow that exists; the manifest's
`ksi:` tags reference real KSI ids.

**Done when:** tests pass, the evidence regenerates cleanly, and a stronger model has checked the KSI list against the source.

---

## F07 · DoD IL5 explainer: what IL5 adds on top of FedRAMP High

- **Wave / mode:** 6 · offline · **review by a stronger model**
- **Depends on:** F05; F10a helps (STIG mapping schema)

**Files:** `docs/compliance/il5.md`, `docs/compliance/il5-gap-table.csv`.

**Steps:**
1. Explain from the CC SRG (cite the version): what the Impact Levels are; what IL5 covers (controlled unclassified
   information and unclassified National Security Systems, per the SRG); and how FedRAMP High relates to it as the
   foundation, with DoD-specific additions.
2. List the IL5 additions from the SRG: DoD-specific controls and parameter values, separation from non-DoD tenants,
   personnel requirements, DoD PKI/CAC authentication, connection through DoD-approved network boundaries, incident
   reporting to DoD, and data location. For each, add a row to the gap table with:
   - requirement (paraphrased, with the SRG section);
   - category: `shaped-for` (this architecture already has the pattern), `buildable` (could be added to the lab), or
     `never-in-a-lab`;
   - what the lab has, or would need;
   - a task link if buildable.
3. Expected buildable items, to confirm against the SRG: Keycloak X.509 client-certificate login (CAC/PIV pattern) with a
   test CA; FIPS 140-validated crypto modules (record honestly whether Talos, the base images and Go binaries can run in
   a FIPS-validated mode); DISA STIG checks for Kubernetes and the host OS (F10, F08); images from a hardened registry.
4. Compare against the DoD's own reference platform in a table: **Platform One Big Bang** and **Iron Bank** hardened
   images. Show what they provide that this lab doesn't, and what this lab's evidence pipeline adds. This is the honest
   "if you were really doing IL5 on Kubernetes, start here" pointer.
5. Cloud options: AWS GovCloud (US), Azure Government, and Google Cloud's IL5 offerings. Verify each provider's current IL5
   listing and the services in scope, with a retrieval date.

**Done when:** the page and the CSV are in the nav, every SRG reference is cited by section, and a stronger model has reviewed it.
