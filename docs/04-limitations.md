# Stated limitations

Naming these explicitly is a stronger signal than pretending they don't exist. Nothing here is
hidden in a footnote — if a claim in the README or control matrix would require one of these
gaps to be closed, the claim doesn't get made.

- **DORA Art. 26 threat-led penetration testing (TLPT) cannot be demonstrated in a lab.**
  TIBER-EU-style red teaming requires defined scope, real threat intelligence, and independent
  testers operating against production. Nothing here substitutes for it; the control matrix
  does not claim Art. 26 coverage.
- **Third-party contractual arrangements (DORA Art. 28–30) are simulated.** The generated
  Register of Information is real (built from actual image inventories and SBOMs), but fields
  describing contracts, exit strategies, and subcontracting chains are lab fixtures — there are
  no real vendor contracts behind them.
- **No relationship with a competent authority.** `drills/lib/clocks.py` computes real deadlines
  from real timestamps, and the classification logic is real. Nothing is ever submitted to a
  regulator; there is no NCA integration, and none is implied.
- **Classification inputs are synthetic.** `drills/lib/classify.py` implements the DORA Art. 18
  RTS criteria as executable logic, but client counts, economic impact figures, and reputational
  impact scores for Meridian Pay are lab fixtures, not measurements of a real business.
- **ISO 27001 requires an ISMS.** Clauses 4–10 — management review, internal audit, continual
  improvement, top-management ownership of risk acceptance — are organisational processes this
  repository does not and cannot implement. Only a subset of Annex A technical/procedural
  controls is addressed; see `docs/02-statement-of-applicability.md`.
- **Single-operator lab.** Segregation of duties is asserted through branch protection and
  required review rules rather than genuinely enforced across multiple humans with distinct
  roles. A real ISMS would require more than one person able to demonstrate this control.
