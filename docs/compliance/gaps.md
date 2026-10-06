# Gaps register

Where this repository **falls short of the text it is mapped to**, or where a claim rests on weaker footing than it
appears to. Every row is also referenced from the article pages. If you are an executive, this is the page that tells
you what *not* to repeat in a meeting.

**Class** says what it would take to close the gap:

- **Offline**: can be built and tested without a cluster.
- **Live**: needs a running cluster to build and verify honestly.
- **Organisational**: people, process or governance, not software.
- **Lab limit**: inherent to a one-person, one-host lab.

| ID | Gap | Text it falls short of | Class | Suggested action |
|---|---|---|---|---|
| G1 | Restores land on the same cluster as the source | DORA Art. 12(3) "physically and logically segregated" | Live | Phase 19: a second cluster and cross-cluster restore |
| G2 | One control-plane node, no redundancy | DORA Art. 12(4); ISO A.8.14 | Lab limit | Three control-plane nodes in a real deployment |
| G3 | Drill verdict ignores the recorded targets (`target_rto_seconds`, `target_rpo_seconds`) | DORA Art. 12(6) | Live | Fail the verdict when measured RTO exceeds target; verify with a drill |
| G4 | Drills are not scheduled | DORA Art. 11(6)(a), 12(2), 24(6) "at least yearly" | Live | A CronWorkflow per scenario plus a cadence record |
| G5 | The same person designs, builds and runs the tests | DORA Art. 24(4) independence | Organisational | A second tester or an external party |
| G6 | No threat-led penetration test | DORA Art. 26 | Organisational | Out of reach for a lab, not claimed |
| G7 | No multi-factor authentication | DORA Art. 9(4)(d); NIS2 21(2)(j); NIST IA-2 | Live | Keycloak OTP or WebAuthn policy |
| G8 | Alerts do not notify staff (no paging or webhook receiver) | DORA Art. 10(2) | Live | A Grafana contact point to a real channel |
| G9 | No branch protection or required review | DORA Art. 9(4)(e) "approved" | Offline (a repo setting) | Require the `tests` and `docs` checks and one review |
| G10 | Backup retention is 3 hours | DORA Art. 12(1)(a) | Live | Tiered schedules sized from a real RPO |
| G11 | Classification thresholds are illustrative, and significant-threat classification (Art. 18(2)) is absent | DORA Art. 18; Delegated Reg. (EU) 2024/1772 | Offline | Implement the RTS criteria and thresholds with tests |
| G12 | Only the initial-notification deadline is computed | DORA Art. 19(4); NIS2 Art. 23(4) | Offline | Add intermediate and final deadlines after checking the RTS |
| G13 | Third-party contract fields are synthetic; register is not the official template | DORA Art. 28(3), 30 | Organisational | Real contracts; the RTS register format |
| G14 | No business impact analysis, risk register, or Statement of Applicability | DORA Art. 11(5); NIS2 21(2)(a); ISO 27001 Cl. 6 | Organisational | Write them. [Scope](../00-scope.md) names `docs/01` and `docs/02` that do not exist |
| G15 | Two historical samples violate the schema; one has a **negative RPO** | Evidence quality | Live | Find the counter-capture bug (hypothesis in [Reading the evidence](../guide/reading-the-evidence.md)), re-run, regenerate the chain deliberately |
| G16 | One age key, one holder; the CA was re-issued after the original key was lost | NIST SC-12; DORA Art. 9(4)(d) | Organisational | Back up the key; add a second recipient |
| G17 | MinIO community edition is frozen (pinned to its last image) | DORA Art. 28; NIS2 21(2)(d) | Offline | Plan a migration to a maintained S3 store |
| G18 | `apko@latest` in CI; GitHub Actions pinned by tag, not SHA | NIST SR-3, SA-11 | **Fixed** | Every action pinned to a commit SHA with a version comment; apko installed from a pinned, checksum-verified release; Dependabot keeps pins current; `tests/test_ci_pinning.py` enforces it (roadmap T07) |
| G19 | Trivy exporter, GLPI and Grafana API tokens are unverified or placeholders | NIST RA-5, IR-4 | Live | Bring the cluster up and verify end to end |
| G20 | No cluster has been booted on the current host since the secrets re-key. All committed evidence predates the new CA and secrets | All evidence-backed claims | Live | Re-run drills after bootstrap and add fresh samples |
| G21 | Clock-synchronisation and security-testing rows have no generated evidence | ISO A.8.17, A.8.29 | Live / Offline | Clock-skew drill; archive CI run output as evidence |
| G22 | `kube-bench`, certificate-expiry monitoring, TLS evidence not built | DORA Art. 24-27; NIST CM-6, SC-13 | Live | Phases 14, 18, 26 |
| G23 | The platform's own reporting timeline model was wrong for delayed classification until the test work | DORA Art. 19 | Offline | **Fixed** in `clocks.py` with tests |
| G24 | Incident post-incident-review text is boilerplate | DORA Art. 13(2) | Organisational | A human completes the review, and the ticket flags it as incomplete |

## What was fixed while writing these docs

These were found by the new tests and are fixed in the same pull requests: the Register of Information generator found no
components after the tier split; `configure-service-groups.sh` did not parse; the clock model for delayed classification (G23).

## How to use this page

- **Executives:** quote [Executive summary](../guide/executive-summary.md) numbers only alongside the relevant row here.
- **Engineers:** rows marked Offline are good first tasks; they need no cluster.
- **Auditors:** this is an honest list, not a complete one. Absence of a row is not assurance.
