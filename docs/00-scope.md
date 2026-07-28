# Scope

This document is written before any infrastructure code, per the build spec. It defines the
notional entity the lab pretends to protect, and settles the regulatory boundary questions that
would otherwise get decided implicitly (and inconsistently) file by file.

## 0.1 The notional entity

**"Meridian Pay"** — a mid-sized, EU-authorised **payment institution** under PSD2, licensed in
Ireland, passporting services into 11 other EU member states. It provides payment initiation,
account information, and card-issuing processing to ~2,400 SME merchants, processing roughly
40 million transactions/year. ~180 staff, no group/parent entity, no banking licence.

This profile is chosen deliberately over a bank or a large payment group:

- It is squarely in scope for **DORA** (Art. 2(1)(a) covers payment institutions authorised
  under PSD2) and, absent DORA, would be an "essential" or "important" entity under **NIS2**
  Annex I/II depending on final national transposition — the lex specialis question in §0.2
  matters precisely because this entity type sits at the boundary.
- It is large enough to be interesting (cross-border, meaningful transaction volume) but not so
  large that "proportionality" becomes a non-issue — proportionality is a real, cited feature of
  both regimes and the entity should be a genuine test of it, not a strawman.

## 0.2 DORA is lex specialis to NIS2 for this entity

NIS2 Art. 4 provides that where sector-specific Union legal acts require essential or important
entities to adopt cybersecurity risk-management measures or to notify incidents, and those
requirements are *at least equivalent in effect* to the corresponding NIS2 obligations, the
sector-specific act applies instead. DORA Chapter II (ICT risk management), Chapter III
(incident reporting), Chapter IV (resilience testing), and Chapter V (third-party risk) are
explicitly identified as such a regime for the financial sector (DORA Art. 1(2), and recital
28 of DORA / recital 28 of NIS2).

**Consequence for this lab:** Meridian Pay's ICT risk management, incident classification and
reporting, resilience testing, and third-party risk management are governed by **DORA**, not
by NIS2's equivalent articles. NIS2 obligations that are *not* displaced (e.g. registration
duties, cooperation with national authorities on matters DORA doesn't cover) are out of scope
here because they don't produce infrastructure or evidence artifacts — they're paperwork
between the entity and its regulator, not something a cluster can demonstrate.

This is why the article map in the build spec (§3) lists both DORA and NIS2 columns side by
side rather than picking one: the *displacement* is the interesting fact, and the drill system
computes both regulatory clocks (§0.4) specifically to make the divergence visible rather than
asserting it in prose.

## 0.3 DORA Art. 16 simplified framework — does not apply

DORA Art. 16(1) lists the entities eligible for the simplified ICT risk-management framework:
small and non-interconnected investment firms, payment institutions **exempted** under PSD2
Art. 32(1), small institutions for occupational retirement provision, electronic money
institutions **exempted** under EMD2 Art. 9(1), and small entities as defined by the
Commission Recommendation on micro, small and medium-sized enterprises, *unless* they are
already excluded from DORA's scope entirely.

Meridian Pay is deliberately modelled as a **fully authorised** PSD2 payment institution, not
one operating under the Art. 32(1) waiver (that waiver is only available to very small payment
institutions below strict turnover thresholds, and it would exempt the entity from PSD2
authorisation itself, not just simplify DORA). At ~40M transactions/year and 11-country
passporting, Meridian Pay would not qualify for the waiver in the first place.

**Consequence:** Meridian Pay is subject to the **full** DORA ICT risk-management framework
(Art. 5–15), not the simplified one. This is the harder, more interesting case, and it's the
one that exercises every row of the control matrix rather than a subset.

## 0.4 Reporting clocks — both computed, divergence surfaced

Even though DORA displaces NIS2 for Meridian Pay's incident-reporting obligations, both clocks
are computed by `drills/lib/clocks.py` (§6.4 of the build spec) because:

1. It makes the lex specialis decision above *verifiable* rather than asserted — anyone can see
   what the NIS2 clock *would* have required and confirm the DORA clock is in fact the binding
   one.
2. The two regimes start the clock on different events — DORA Art. 19 starts from
   **classification as major**, capped at 24h from **detection**; NIS2 Art. 23 starts from
   **awareness**. In a single incident timeline these are not the same instant, and the gap
   between them is exactly the kind of thing a lab can measure and a whitepaper can only
   describe.

## 0.5 ISO 27001 — Annex A control subset, not an ISMS

ISO/IEC 27001 certifies Clauses 4–10: a management system (context, leadership, planning,
support, operation, evaluation, improvement). Annex A is a control menu referenced by the
Statement of Applicability, not a certifiable object on its own.

This repository implements **technical controls that map to specific Annex A controls**
(A.5.1–A.5.30, A.8.x as listed in the build spec's article map). It does **not** implement an
ISMS: there is no management review, no internal audit programme, no top-management-owned risk
acceptance process, no HR/supplier-contract lifecycle. `docs/02-statement-of-applicability.md`
states explicitly which Annex A controls are addressed and marks the rest "not implemented —
lab scope."

## 0.6 What "compliant" does not mean here

Restated from the build spec §0, because it belongs in the scope document too:

- Running this repository does not make Meridian Pay, or anyone else, DORA/NIS2/ISO 27001
  compliant. DORA and NIS2 are obligations on regulated *entities*; ISO 27001 certifies an
  *organisation's management system* following an external audit. A GitOps repo can implement
  controls and produce evidence; it cannot be audited, cannot hold a certificate, and has no
  regulator relationship.
- Every claim in this repository's README and docs is a claim about **what the code in this
  repository does**, not about the compliance status of any real organisation.

## 0.7 Open items carried to later docs

- `docs/01-risk-assessment.md` — Meridian Pay's notional risk register (Phase 0/1 follow-on).
- `docs/02-statement-of-applicability.md` — full Annex A applicability table.
- `docs/04-limitations.md` — stated limitations (build spec §11), written alongside this file.
