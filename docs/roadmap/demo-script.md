# Demo script: "Measured, not asserted"

A 25-minute live demo for financial-sector audiences in Dublin: hiring managers, heads of ICT
risk, CISOs, and resilience leads. It explains DORA through a working system and shows why you
are the person to build it at their firm. It assumes the [roadmap](README.md) is done through
T20 (waves 0–3).

> **Fact-check before presenting.** Article references were checked against Regulation (EU)
> 2022/2554 at the time of writing. Re-confirm anything marked ⚑ against the current Central Bank
> of Ireland and ESA publications the week of the talk. Never state a date or figure you haven't
> checked that week.

---

## The one idea to leave in their heads

> "Since January 2025 every DORA firm has to *show* it can recover, detect, classify and report
> in time. Most can show policies. I built a platform that produces the proof by machine, on a
> schedule, mapped to the article it satisfies, and I can tell you exactly where it falls short."

Everything below serves that sentence. The last clause (honesty about gaps) is what separates you
from vendors pitching dashboards.

---

## Before you start (T-30 min)

- [ ] VM up for at least 2 hours, all Argo CD apps Synced/Healthy. **Never reboot on the day.**
- [ ] Tailscale connected. Browser tabs open and logged in: Argo CD, Grafana (RTO/RPO trend +
      vulnerability dashboards), GLPI, Hubble UI.
- [ ] Two terminals: (A) an SSH session in the repo on the VM, (B) a local clone for the offline
      tamper demo. Font size 18+.
- [ ] Fallback ready: the asciinema recording and screenshots from T20, opened locally.
- [ ] Phone on loud if T13 (alert notifications) is built.
- [ ] Pick the evidence samples you will show. **Not** `ns-restore-20260729135024.json`: it has
      the negative RPO (G15).

---

## Running order

| # | Min | Section | DORA anchor | What's on screen |
|---|---|---|---|---|
| 0 | 1 | Hook | — | Title slide or the README |
| 1 | 3 | DORA in three minutes | Art. 1, 2, 4, 5–45 | One slide: the five pillars |
| 2 | 1 | **Kick off the drill** | Art. 11, 12, 24–25 | Terminal A |
| 3 | 2 | The platform | Art. 9 | Argo CD app tree |
| 4 | 3 | Protection you can see | Art. 9 | Kyverno denial, Hubble denied flow |
| 5 | 4 | **Drill result** | Art. 11, 12 | Terminal A, Grafana trend |
| 6 | 4 | Incident to regulator clock | Art. 17–19 | GLPI ticket, classification output |
| 7 | 2 | Detection | Art. 10 | Credential-compromise alert, ATT&CK labels |
| 8 | 2 | Third parties and supply chain | Art. 28–30 | Signed image, SBOM, Register of Information |
| 9 | 2 | **Evidence you can't quietly edit** | Art. 9, 12 | Terminal B tamper demo, OSCAL |
| 10 | 2 | What this doesn't do | Art. 26, 12(3), 24(4) | Gaps register |
| 11 | 1 | Why me, and what I'd do first | — | Closing slide |

### 0 · Hook (1 min)

"DORA has applied since 17 January 2025. Ask any firm whether it can restore a critical service
in its stated recovery time, and it'll say yes and show you a policy. Ask how many seconds the
last restore took, how many records it lost, and when the regulator clock would have expired, and
the room goes quiet. I'm going to answer those three questions live, in about four minutes."

### 1 · DORA in three minutes (3 min)

Keep it to one slide. Audiences in Dublin know DORA exists. What they value is someone who can
place it precisely.

- **What it is:** Regulation (EU) 2022/2554. It is directly applicable, so there is no Irish
  transposition. The **Central Bank of Ireland** is the competent authority for Irish financial entities ⚑.
- **Five pillars:** ICT risk management (Ch. II, Art. 5–16), incident management, classification
  and reporting (Ch. III, Art. 17–23), digital operational resilience testing (Ch. IV, Art. 24–27),
  ICT third-party risk (Ch. V, Art. 28–44), and information sharing (Ch. VI, Art. 45).
- **Lex specialis:** for financial entities, DORA's ICT rules take precedence over NIS2's
  equivalents (NIS2 Art. 4). "I compute both clocks anyway, and I'll show you why the difference matters."
- **Proportionality:** Art. 4, plus the simplified framework in Art. 16 for smaller entities. The
  notional tenant here is a small EU payment institution (`docs/00-scope.md`).
- **Irish texture (pick one, verify it ⚑):** the CBI's 2021 Cross-Industry Guidance on Operational
  Resilience and on Outsourcing predate DORA and still shape supervisory expectations. Register of
  Information submissions now run through the CBI to the ESAs. Dublin hosts the EU headquarters of
  several hyperscalers that sit inside the ESAs' critical-third-party oversight regime.

### 2 · Kick off the drill first (1 min)

A restore takes minutes, so start it now and talk while it runs.

```bash
make drill SCENARIO=ns-restore
```

"This deletes a tenant's namespace, a payment ledger writing one hash-chained record a second, and
restores it from backup into a fresh namespace. Restoring over the original proves nothing. We'll
come back for the numbers."

### 3 · The platform (2 min)

Argo CD app tree. "Everything you see is declared in Git and reconciled. No one runs `kubectl apply`
by hand, so the Git history *is* the change record (Art. 9(4)(e) change management). Every chart and
image is pinned." Show the AppProject restrictions: "Argo CD is the most powerful identity in the
cluster, so it gets guardrails too."

If T02 is built, add: "Every time this lab is stood up it generates its own certificate authority
and credentials. Nothing secret lives in Git. In a bank the root would sit in an HSM, and I've
written up that difference."

### 4 · Protection you can see (3 min)

Terminal A, a privileged pod (rehearse the exact command and namespace):

```bash
kubectl -n canary run demo-priv --image=busybox:1.36 --privileged --restart=Never -- sleep 1
```

It is denied by Kyverno enforcing Pod Security Standards `restricted`. "Note that the exceptions
are files too." Open `docs/exceptions/tetragon.md`: scoped, reasoned, a named risk accepter, and a
compensating control. "Exceptions are where judgement shows. Silent ones are where audits fail."

Then Hubble: show a denied flow between namespaces. Default-deny across every platform namespace.

### 5 · The drill result (4 min), the centrepiece

Back to Terminal A. Read the record aloud, slowly:

- **RTO**: measured seconds from fault injection to the first passing probe. "Not a number someone
  typed into a policy."
- **RPO**: an *exact count of records lost*, because the canary numbers every record.
- **Integrity check**: the restored ledger's hash chain verifies. "A restore that succeeds but
  quietly corrupts data is the failure most restore tests miss."
- **Verdict**: pass or fail against the *target* (once T09 is built). "If we'd missed the target
  you'd see fail here, and failed drills are kept, because they're the most valuable evidence."

Switch to the Grafana RTO/RPO trend: "This runs on a schedule (T11), so this is a history, not a
staged run. Art. 11(6) and Art. 24 want testing that is regular, not a one-off before an audit."

### 6 · From incident to regulator clock (4 min)

Show the classification output and the GLPI ticket.

- "Art. 18 and Delegated Regulation 2024/1772 define when an incident is *major*. Two criteria here
  come from measured data (duration and data loss). The rest are synthetic fixtures for a
  notional firm, and the code says so in its docstring."
- **The divergence slide** (T24 page, if built): DORA's initial-notification clock runs from
  **classification** (4 hours), capped at 24 hours from awareness. NIS2's early warning runs from
  **awareness** (24 hours). "Same incident, two clocks, started by different events. If your
  process doesn't timestamp the classification decision separately, you can't prove you met DORA's
  deadline. The ticket shows both, computed from real timestamps."
- Mention the delayed-classification edge case PR #2 fixed: "When classification comes late, the
  naïve formula produces a deadline that's already passed. I found that with tests, against the
  delegated regulation ⚑."

### 7 · Detection (2 min)

The credential-compromise drill (from a recording, or live if timing allows): a stolen
ServiceAccount token, then a shell spawned in the container. Tetragon sees the `execve` via eBPF,
and the Grafana alert fires (phone buzzes if T13 is built). Show the ATT&CK labels on the rule
(T1059.004) and the measured detection latency. "Art. 10 asks for detection mechanisms. This
measures how fast they are."

### 8 · Third parties and supply chain (2 min)

- The tenant image is built from a minimal Wolfi base, **signed keylessly** in CI, with an SBOM
  attestation. Kyverno refuses to run it unless the signature matches *this repo's exact workflow
  identity*.
- The Register of Information (Art. 28(3)) is **generated** from the real image and chart inventory,
  not maintained in a spreadsheet. "The contract fields are synthetic. That's on the limitations page."
- The Trivy dashboard: live CVEs cross-referenced with CISA's Known Exploited Vulnerabilities list,
  with days-open against an SLA.

### 9 · Evidence you can't quietly edit (2 min)

Terminal B, a local clone. This works offline, so it's safe even if the VM misbehaves:

```bash
make evidence-verify                               # integrity_check: pass
sed -i 's/"measured_rto_seconds": 110/"measured_rto_seconds": 42/' \
  docs/evidence/samples/ns-restore-20260728152755.json
make evidence-verify                               # integrity_check: fail, file_hash mismatch
git checkout -- docs/evidence/samples/
```

Rehearse the `sed` against whichever sample you choose, and check that the value matches.
"Every evidence file is hash-chained, and CI signs the chain head through Sigstore's public
transparency log. If someone improves an RTO after the fact, it shows." Then show the per-control
evidence folders and the OSCAL export: "One artifact, mapped to DORA, NIS2, ISO 27001, NIST 800-53
and ATT&CK at once. That's how you stop doing the same audit five times."

### 10 · What this doesn't do (2 min)

Open `docs/compliance/gaps.md`. Pick three:

- **TLPT (Art. 26):** needs independent testers and threat intelligence. A lab can't do it, and I don't claim it.
- **Restores land on the same cluster** (Art. 12(3) wants segregation). Fixing that is the DR tier on the roadmap.
- **Independence (Art. 24(4)):** I designed, built and tested this alone.

"Every one of these is written down with the article it falls short of. I'd expect a supervisor to
find them, so I found them first."

### 11 · Why me (1 min)

Tailor this to the firm. Structure:

1. **What you saw:** someone who reads the regulation text, turns it into running controls, and
   measures them.
2. **What I'd do in the first 90 days at your firm:** pick one critical or important function. Map
   its ICT dependencies to the Register of Information. Run one restore test with *measured* RTO/RPO
   against its stated tolerance. Timestamp classification separately in the incident process. Then
   report the gaps honestly.
3. **The ask:** a conversation about where your resilience programme is today.

---

## Likely questions (prepare one-line answers)

| Question | Short answer |
|---|---|
| "Would this run in our bank?" | The patterns would; the components are swappable. Loki → your SIEM, GLPI → ServiceNow, MinIO → your object store. The *interface* is the drill record schema |
| "Isn't this just chaos engineering?" | Chaos engineering tests a hypothesis. This adds the regulatory layer: classification, clocks, an evidence chain, control mapping |
| "How does this help with TLPT?" | It doesn't replace TLPT. It is the Art. 25 testing programme that sits underneath it, and it generates the baseline TLPT findings are measured against |
| "What about the CTPP regime?" | Art. 31–44 oversee the providers, not you. You still owe Art. 28 due diligence, and the generated Register is the starting point ⚑ |
| "Why Kubernetes?" | It's what many firms are migrating to, and it makes recovery declarative, so it can be tested on a schedule |
| "What was hardest?" | Pick a real "caught live" story from the CHANGELOG, e.g. the hash chain catching a restore that looked fine |
| "Is the classification real?" | Two criteria are measured; the rest are labelled synthetic fixtures. Thresholds are illustrative (gap G11) |

## If something breaks on stage

- **Drill hangs:** "Live demos, so this is why we keep recordings." Play the asciinema and carry on.
  Note it in the CHANGELOG afterwards. It's evidence too.
- **A UI won't load:** use the screenshots. Terminal B's tamper demo needs no cluster.
- **Never** hot-fix the cluster in front of the audience.
